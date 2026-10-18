//
//  ExerciseDemos.swift
//  FormCoach
//
//  Procedural technique demos: each exercise is a smooth looping skeleton
//  animation built from the same joint model the analyzer scores against.
//  Every fault FormCoach checks has a variant that plays the mistake with
//  the affected joints lit up, so the library can show what good form is —
//  and what it looks like when it goes wrong.
//

import Foundation
import CoreGraphics

/// Which way the demo figure faces.
enum DemoView: String, CaseIterable {
    case side, front

    var label: String { rawValue.capitalized }
}

/// One skeleton pose, authored in angles from a stick-figure rig.
/// Limb angles are degrees measured from straight down, positive toward the
/// facing direction (+x). `bend` rotates the forearm/shin further forward.
nonisolated struct DemoPose: Sendable {
    var hipX: Double = 0.5
    var hipY: Double = 0.44
    var torso: Double = 4
    var nearArm: Double = 4
    var nearBend: Double = 0
    var farArm: Double?
    var farBend: Double?
    var nearLeg: Double = 4
    var nearKnee: Double = 4
    var farLeg: Double?
    var farKnee: Double?
    /// Chin pushed forward (neck crank).
    var headTilt: Double = 0
    /// One shoulder dropped, in normalized units (shoulder tilt fault).
    var shoulderTilt: Double = 0

    static func lerp(_ a: DemoPose, _ b: DemoPose, _ u: Double) -> DemoPose {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * u }
        var p = DemoPose()
        p.hipX = mix(a.hipX, b.hipX)
        p.hipY = mix(a.hipY, b.hipY)
        p.torso = mix(a.torso, b.torso)
        p.nearArm = mix(a.nearArm, b.nearArm)
        p.nearBend = mix(a.nearBend, b.nearBend)
        p.farArm = a.farArm.map { mix($0, b.farArm ?? $0) } ?? b.farArm
        p.farBend = a.farBend.map { mix($0, b.farBend ?? $0) } ?? b.farBend
        p.nearLeg = mix(a.nearLeg, b.nearLeg)
        p.nearKnee = mix(a.nearKnee, b.nearKnee)
        p.farLeg = a.farLeg.map { mix($0, b.farLeg ?? $0) } ?? b.farLeg
        p.farKnee = a.farKnee.map { mix($0, b.farKnee ?? $0) } ?? b.farKnee
        p.headTilt = mix(a.headTilt, b.headTilt)
        p.shoulderTilt = mix(a.shoulderTilt, b.shoulderTilt)
        return p
    }
}

// MARK: - Catalog

nonisolated enum ExerciseDemos {

    /// Loop length at 1× speed, in seconds.
    static func duration(for exercise: Exercise) -> Double {
        switch exercise {
        case .squat: 2.4
        case .pushUp: 2.2
        case .lunge: 2.6
        case .plank: 3.2
        case .jumpingJack: 1.8
        case .bicepCurl: 2.2
        case .run: 1.1
        case .skiErg: 1.8
        case .sledPush: 1.6
        case .sledPull: 1.7
        case .burpeeBroadJump: 3.6
        case .row: 2.0
        case .farmersCarry: 1.6
        case .sandbagLunge: 2.6
        case .wallBall: 2.4
        }
    }

    /// Views to offer, primary first.
    static func views(for exercise: Exercise) -> [DemoView] {
        switch exercise {
        case .jumpingJack: [.front, .side]
        case .squat, .bicepCurl, .wallBall: [.side, .front]
        default: [.side]
        }
    }

    /// Some faults only read from a specific angle (shoulder tilt is invisible side-on).
    static func view(for exercise: Exercise, fault: String?) -> DemoView {
        switch (exercise, fault) {
        case (.farmersCarry, "shoulder_tilt"): .front
        case (.squat, "knee_drift"): .front
        default: views(for: exercise)[0]
        }
    }

    /// Playback rate for tempo-related faults.
    static func speed(fault: String?) -> Double {
        switch fault {
        case "fast_tempo": 1.7
        case "slow_tempo", "low_cadence": 0.55
        default: 1
        }
    }

    // MARK: Pose at time

    /// Skeleton pose for a demo at normalized cycle time `t` (0–1, loops).
    static func pose(for exercise: Exercise, t: Double, fault: String?, view: DemoView) -> DemoPose {
        let t = t.truncatingRemainder(dividingBy: 1)
        if view == .front, exercise != .farmersCarry {
            return frontPose(for: exercise, t: t, fault: fault)
        }
        return sidePose(for: exercise, t: t, fault: fault)
    }

    private static func sidePose(for exercise: Exercise, t: Double, fault: String?) -> DemoPose {
        let d = wave(t)          // 0 → 1 → 0 smooth rep cycle
        var p = DemoPose()
        p.farArm = nil
        p.farBend = nil
        p.farLeg = nil
        p.farKnee = nil

        switch exercise {
        case .squat:
            let depth = 0.17 * (fault == "shallow_depth" ? 0.45 : 1)
            p.hipY = 0.44 - depth * d
            p.torso = 4 + 14 * d + (fault == "torso_lean" ? 22 * d : 0)
            p.nearArm = 8 + 75 * d
            p.nearLeg = 4 + 92 * d
            p.nearKnee = 4 + 98 * d
            if fault == "knee_drift" {
                p.nearLeg += 18 * d
                p.nearKnee -= 22 * d
            }

        case .pushUp:
            let bend = (fault == "shallow_depth" ? 42 : 82) * d
            p.hipY = 0.44 - 0.10 * d
            p.torso = 88 - 8 * d
            p.nearArm = 0
            p.nearBend = -bend
            p.nearLeg = -8
            p.nearKnee = 8
            if fault == "hip_sag" { p.hipY -= 0.09 * d }
            if fault == "hip_pike" { p.hipY += 0.15 * d }

        case .lunge, .sandbagLunge:
            let depth = 0.16 * (fault == "shallow_depth" ? 0.5 : 1)
            let bag = exercise == .sandbagLunge
            p.hipY = 0.46 - depth * d
            p.torso = 4 + 8 * d + (fault == "torso_lean" ? 20 * d : 0)
            if bag {
                p.nearArm = 12
                p.nearBend = 118
            } else {
                p.nearArm = 6
                p.nearBend = 0
            }
            p.nearLeg = 12 + 74 * d
            p.nearKnee = 8 + 78 * d
            p.farLeg = -14 - 26 * d
            p.farKnee = 6 + 50 * d
            if fault == "knee_over_toe" {
                p.nearLeg += 20 * d
                p.nearKnee -= 30 * d
            }
            if fault == "knee_no_touch" {
                p.farKnee = 6 + 14 * d   // back knee hovers above the floor
            }

        case .plank:
            p.hipY = 0.42 + 0.008 * sin(4 * .pi * t)
            p.torso = 88
            p.nearArm = -4
            p.nearBend = 0
            p.nearLeg = -6
            p.nearKnee = 6
            if fault == "hip_sag" { p.hipY = 0.33 }
            if fault == "hip_pike" { p.hipY = 0.57 }
            if fault == "neck_crank" { p.headTilt = 40 }

        case .jumpingJack:
            p.hipY = 0.44 - 0.02 * d
            p.nearArm = 6 + 150 * d
            p.nearLeg = 4 + 36 * d
            p.nearKnee = 4
            if fault == "incomplete_raise" { p.nearArm = 6 + 100 * d }
            if fault == "arm_asymmetry" {
                p.farArm = 6 + 92 * d
                p.farBend = 0
            }

        case .bicepCurl:
            p.nearArm = 4
            p.nearBend = 6 + 138 * d
            p.nearLeg = 3
            p.nearKnee = 3
            p.torso = 4
            if fault == "incomplete_extension" { p.nearBend = 55 + 95 * d }
            if fault == "incomplete_contraction" { p.nearBend = 6 + 90 * d }
            if fault == "elbow_drift" { p.nearArm = 4 + 26 * d; p.nearBend = 6 + 118 * d }
            if fault == "body_swing" { p.torso = 22 * d }

        case .run:
            let phase = 2 * .pi * t
            let stride = fault == "overstriding" ? 56.0 : 38.0
            p.hipY = 0.46 + 0.012 * sin(2 * phase) + (fault == "heavy_bounce" ? 0.05 * max(0, sin(2 * phase)) : 0)
            p.torso = fault == "run_lean" ? 30 : 8
            p.nearArm = -28 * sin(phase)
            p.nearBend = 85
            p.farArm = 28 * sin(phase)
            p.farBend = 85
            p.nearLeg = 14 + stride * sin(phase)
            p.nearKnee = 34 + 10 * sin(phase)
            p.farLeg = 14 - stride * sin(phase)
            p.farKnee = 34 - 10 * sin(phase)

        case .skiErg:
            let pull = fault == "short_pull" ? 90.0 : 145.0
            p.hipY = 0.44 - 0.03 * d
            p.torso = (fault == "no_hinge" ? 12 : 55) * d + (fault == "pull_hunch" ? 14 * d : 0)
            p.nearArm = 165 - pull * d
            p.nearBend = 0
            p.nearLeg = 2 + 28 * d
            p.nearKnee = 2 + 30 * d
            if fault == "squatting" {
                p.nearLeg = 2 + 55 * d
                p.nearKnee = 2 + 75 * d
                p.hipY = 0.44 - 0.12 * d
                p.torso = 15 * d
            }
            if fault == "short_reach" { p.nearArm = 138 - pull * 0.8 * d }
            if fault == "arms_only" {
                p.nearLeg = 4
                p.nearKnee = 4
                p.hipY = 0.44
            }

        case .sledPush:
            p.hipY = 0.40
            p.torso = fault == "too_upright" ? 12 : 42
            p.nearArm = 35
            p.nearBend = fault == "arms_collapsed" ? -45 : 0
            p.farArm = 35
            p.farBend = p.nearBend
            let drive = fault == "short_drive" ? 20.0 : 45.0
            let phase = 2 * .pi * t
            p.nearLeg = 25 + drive * sin(phase)
            p.nearKnee = 25 + 30 * max(0, sin(phase))
            p.farLeg = 25 - drive * sin(phase)
            p.farKnee = 25 + 30 * max(0, -sin(phase))

        case .sledPull:
            let hunched = fault == "pull_hunch"
            p.torso = hunched ? 15 : (fault == "standing_tall" ? 8 : -20 - 8 * d)
            p.nearArm = fault == "standing_tall" ? 40 - 20 * d : 60 - 45 * d
            p.nearBend = 0
            p.farArm = p.nearArm + 10
            p.farBend = 0
            if fault == "arms_only" {
                p.nearBend = -40 * max(0, sin(2 * .pi * t))
                p.nearLeg = 5
                p.nearKnee = 5
                p.farLeg = -5
                p.farKnee = 5
            } else {
                p.nearLeg = 15
                p.nearKnee = 15
                p.farLeg = -15
                p.farKnee = 15
            }

        case .burpeeBroadJump:
            return burpeePose(t: t, fault: fault)

        case .row:
            p = rowPose(t: t, fault: fault)

        case .farmersCarry:
            let phase = 2 * .pi * t
            p.hipY = 0.44 + 0.008 * sin(2 * phase)
            p.torso = fault == "torso_lean" ? 18 : 3
            p.nearArm = 2
            p.nearBend = fault == "bent_arms" ? 38 : 0
            p.farArm = 2
            p.farBend = p.nearBend
            p.nearLeg = 18 * sin(phase)
            p.nearKnee = 15 + 10 * sin(phase)
            p.farLeg = -18 * sin(phase)
            p.farKnee = 15 - 10 * sin(phase)

        case .wallBall:
            let depth = 0.18 * (fault == "shallow_depth" ? 0.5 : 1)
            p.hipY = 0.26 + 0.19 * d
            p.torso = 8 + 8 * d + (fault == "torso_lean" ? 18 * d : 0)
            p.nearArm = 55 + (fault == "no_extension_throw" ? 70 : 115) * d
            p.nearBend = 65 * (1 - d)
            p.nearLeg = 8 + 88 * d
            p.nearKnee = 8 + 94 * d
            if fault == "knee_drift" {
                p.nearLeg += 16 * d
                p.nearKnee -= 20 * d
            }
        }
        return p
    }

    /// Burpee broad jump: piecewise keyframes (stand → squat → chest down →
    /// get up → flight → land → stand).
    private static func burpeePose(t: Double, fault: String?) -> DemoPose {
        let chestUp = fault == "chest_not_down"
        let noJump = fault == "short_jump"
        let keys: [(Double, DemoPose)] = [
            (0.00, DemoPose(hipY: 0.44, torso: 5)),
            (0.14, DemoPose(hipY: 0.24, torso: 60, nearArm: 30, nearBend: 0)),
            (0.28, DemoPose(hipY: chestUp ? 0.26 : 0.18, torso: 88, nearArm: 0, nearBend: chestUp ? -55 : -78, nearLeg: -8, nearKnee: 8)),
            (0.38, DemoPose(hipY: 0.20, torso: 88, nearArm: 0, nearBend: 0, nearLeg: -8, nearKnee: 8)),
            (0.50, DemoPose(hipY: 0.28, torso: 55, nearArm: 20, nearBend: 0, nearLeg: 60, nearKnee: 100)),
            (0.62, DemoPose(hipX: noJump ? 0.5 : 0.5, hipY: noJump ? 0.50 : 0.64, torso: 0, nearArm: noJump ? 40 : 20, nearLeg: noJump ? 10 : 45, nearKnee: noJump ? 15 : 90)),
            (0.76, DemoPose(hipX: noJump ? 0.5 : 0.5, hipY: 0.26, torso: 50, nearArm: 30, nearLeg: 55, nearKnee: 85)),
            (0.88, DemoPose(hipY: 0.40, torso: 15, nearArm: 12, nearLeg: 15, nearKnee: 18)),
            (1.00, DemoPose(hipY: 0.44, torso: 5)),
        ]
        return sample(keys: keys, t: t, slowGround: fault == "slow_getup")
    }

    /// Rowing: legs → body → arms on the drive, reverse on the recovery.
    private static func rowPose(t: Double, fault: String?) -> DemoPose {
        var p = DemoPose()
        let catchLeg = fault == "short_catch" ? 45.0 : 65.0
        let catchTorso = fault == "overreach" ? 40.0 : 28.0
        let finishTorso = fault == "over_layback" ? -32.0 : -8.0
        let catchArm = fault == "overreach" ? 95.0 : 80.0

        var leg: Double, torso: Double, arm: Double
        if t < 0.5 {
            // Drive: legs first, then body swing, then arm pull.
            leg = catchLeg - (catchLeg - 2) * ramp(t, 0, 0.42)
            torso = catchTorso - (catchTorso - finishTorso) * ramp(t, 0.08, 0.5)
            arm = t < 0.3 ? catchArm : catchArm - (catchArm + 35) * ramp(t, fault == "early_arms" ? 0 : 0.3, fault == "early_arms" ? 0.55 : 0.62)
        } else {
            // Recovery: arms away, body over, knees bend last.
            arm = -35 + (catchArm + 35) * ramp(t, 0.55, 0.8)
            torso = finishTorso + (catchTorso - finishTorso) * ramp(t, 0.6, 0.9)
            leg = 2 + (catchLeg - 2) * ramp(t, 0.62, 0.95)
        }
        p.hipY = 0.40 + 0.02 * (1 - leg / max(catchLeg, 1))
        p.torso = torso
        p.nearArm = arm
        p.nearBend = fault == "early_arms" && t < 0.3 ? -35 : 0
        p.nearLeg = leg
        p.nearKnee = leg
        return p
    }

    // MARK: Front view

    private static func frontPose(for exercise: Exercise, t: Double, fault: String?) -> DemoPose {
        let d = wave(t)
        var p = DemoPose()
        switch exercise {
        case .jumpingJack:
            p.hipY = 0.44 - 0.02 * d
            p.nearArm = fault == "incomplete_raise" ? 6 + 100 * d : 6 + 160 * d
            if fault == "arm_asymmetry" {
                p.farArm = 6 + 95 * d
                p.farBend = 0
            }
            p.nearLeg = 4 + 24 * d
            p.nearKnee = 4

        case .squat:
            let depth = 0.17 * (fault == "shallow_depth" ? 0.45 : 1)
            p.hipY = 0.44 - depth * d
            p.nearArm = 8 + 10 * d
            p.nearLeg = fault == "knee_drift" ? 8 - 26 * d : 6 + 12 * d
            p.nearKnee = 6

        case .bicepCurl:
            p.nearArm = 6
            p.nearBend = 6 + 138 * d
            p.nearLeg = 5
            p.nearKnee = 5
            if fault == "body_swing" { p.hipX = 0.5 + 0.03 * d }

        case .wallBall:
            let depth = 0.18 * (fault == "shallow_depth" ? 0.5 : 1)
            p.hipY = 0.26 + 0.19 * d
            p.nearArm = 40 + (fault == "no_extension_throw" ? 85 : 130) * d
            p.nearBend = 20 * (1 - d)
            p.nearLeg = fault == "knee_drift" ? 8 - 22 * d : 6 + 12 * d
            p.nearKnee = 6

        case .farmersCarry:
            p.hipY = 0.44 + 0.006 * sin(4 * .pi * t)
            p.nearArm = 3
            p.nearBend = fault == "bent_arms" ? 38 : 0
            p.nearLeg = 6 + 4 * sin(2 * .pi * t)
            p.nearKnee = 6
            if fault == "shoulder_tilt" { p.shoulderTilt = 0.03 }
            if fault == "torso_lean" { p.hipX = 0.53 }

        default:
            return sidePose(for: exercise, t: t, fault: fault)
        }
        return p
    }

    // MARK: Standards & faults

    /// What counts as a valid rep / stroke / segment for this movement.
    static func standard(for exercise: Exercise) -> [String] {
        switch exercise {
        case .squat: [
            "Feet about hip-width, toes turned slightly out",
            "Hips drop below the knees at the bottom",
            "Knees track out over the toes",
            "Stand fully tall at the top of every rep",
        ]
        case .pushUp: [
            "Body forms one straight line head to heels",
            "Chest touches the floor on every rep",
            "Elbows about 45° from your ribs",
            "Press all the way up to locked arms",
        ]
        case .lunge: [
            "Long enough step that both knees reach 90°",
            "Back knee lowers all the way to the floor",
            "Front knee stacks over the ankle",
            "Torso stays tall through the whole rep",
        ]
        case .plank: [
            "One straight line: shoulders, hips, ankles",
            "Elbows stacked under the shoulders",
            "Glutes and core braced the whole time",
            "Neck stays in line with your spine",
        ]
        case .jumpingJack: [
            "Arms reach fully overhead at the top",
            "Hands pass above your head",
            "Both sides move evenly together",
            "Light knees, steady rhythm",
        ]
        case .bicepCurl: [
            "Elbows pinned to your ribs",
            "Arms fully straight at the bottom",
            "Curl to a full contraction at the top",
            "No swinging or leaning to help",
        ]
        case .run: [
            "Foot lands under your hips, not out front",
            "Quick, light steps — 170+ per minute",
            "Tall posture, leaning only from the ankles",
            "Smooth stride with no vertical bounce",
        ]
        case .skiErg: [
            "Sit into a low, braced stance",
            "Hinge from the hips to load the pull",
            "Pull the handles down past your hips",
            "Reach fully overhead on every return",
        ]
        case .sledPush: [
            "Lean in at roughly 45° into the sled",
            "Arms locked straight against the poles",
            "Drive your knees with short, powerful steps",
            "Push through the balls of your feet",
        ]
        case .sledPull: [
            "Low, braced stance facing the sled",
            "Pull the rope hand over hand to your chest",
            "Stay seated low — don't stand up as you pull",
            "Hips power the pull, not just the arms",
        ]
        case .burpeeBroadJump: [
            "Chest and thighs touch the floor",
            "Get up in one quick, efficient motion",
            "Two-foot take-off and two-foot landing",
            "Swing your arms and cover real ground",
        ]
        case .row: [
            "Catch with shins vertical and arms straight",
            "Drive: legs first, then body, then arms",
            "Pull the handle past your hips",
            "Finish leaning back just a touch — 11 o'clock",
        ]
        case .farmersCarry: [
            "Weights hang at your sides, arms long",
            "Shoulders stay level under the load",
            "Walk tall with ribs stacked over hips",
            "Steady, controlled steps — no tilting",
        ]
        case .sandbagLunge: [
            "Bag rests across both shoulders",
            "Step into a long lunge down the lane",
            "Back knee touches the floor every rep",
            "Torso stays tall under the bag",
        ]
        case .wallBall: [
            "Hips drop below the knees at the bottom",
            "Ball held at the chest through the descent",
            "Drive through the legs and extend fully",
            "Throw to hit the target, then catch and flow",
        ]
        }
    }

    /// The faults FormCoach checks for this exercise: key, short label and cue.
    static func faults(for exercise: Exercise) -> [(key: String, label: String, cue: String)] {
        let keys: [String]
        switch exercise {
        case .squat: keys = ["shallow_depth", "knee_drift", "torso_lean", "fast_tempo"]
        case .pushUp: keys = ["shallow_depth", "hip_sag", "hip_pike", "fast_tempo"]
        case .lunge: keys = ["shallow_depth", "torso_lean", "knee_over_toe", "fast_tempo"]
        case .plank: keys = ["hip_sag", "hip_pike", "neck_crank", "short_hold"]
        case .jumpingJack: keys = ["incomplete_raise", "arm_asymmetry", "fast_tempo"]
        case .bicepCurl: keys = ["incomplete_extension", "incomplete_contraction", "elbow_drift", "body_swing"]
        case .run: keys = ["overstriding", "low_cadence", "heavy_bounce", "run_lean"]
        case .skiErg: keys = ["short_pull", "no_hinge", "squatting", "short_reach"]
        case .sledPush: keys = ["too_upright", "short_drive", "arms_collapsed"]
        case .sledPull: keys = ["standing_tall", "arms_only", "pull_hunch"]
        case .burpeeBroadJump: keys = ["chest_not_down", "slow_getup", "short_jump"]
        case .row: keys = ["short_catch", "early_arms", "over_layback", "overreach"]
        case .farmersCarry: keys = ["torso_lean", "shoulder_tilt", "bent_arms"]
        case .sandbagLunge: keys = ["knee_no_touch", "torso_lean", "knee_over_toe"]
        case .wallBall: keys = ["shallow_depth", "no_extension_throw", "knee_drift", "torso_lean"]
        }
        return keys.map { key in
            let label: String
            let cue: String
            switch key {
            case "shallow_depth": label = "Shallow depth"; cue = "Sink until your thighs reach parallel."
            case "knee_drift": label = "Knees cave in"; cue = "Press your knees out over your toes."
            case "torso_lean": label = "Chest falls forward"; cue = "Brace your core and stay tall."
            case "fast_tempo": label = "Rushed tempo"; cue = "Slow down and control each rep."
            case "slow_tempo": label = "Grinding tempo"; cue = "Drive up with intent."
            case "hip_sag": label = "Hips sag"; cue = "Squeeze your glutes into one straight line."
            case "hip_pike": label = "Hips pike up"; cue = "Lower your hips into the straight line."
            case "neck_crank": label = "Neck craned"; cue = "Keep your neck in line with your spine."
            case "short_hold": label = "Short hold"; cue = "Build toward longer, solid holds."
            case "incomplete_raise": label = "Arms stop short"; cue = "Raise fully overhead every rep."
            case "arm_asymmetry": label = "Arms uneven"; cue = "Move both hands together."
            case "incomplete_extension": label = "No full extension"; cue = "Straighten completely at the bottom."
            case "incomplete_contraction": label = "No peak squeeze"; cue = "Curl to a full contraction."
            case "elbow_drift": label = "Elbow drifts"; cue = "Pin your elbow to your ribs."
            case "body_swing": label = "Body swings"; cue = "Keep your torso still — no momentum."
            case "overstriding": label = "Overstriding"; cue = "Land with your foot under your hips."
            case "low_cadence": label = "Low cadence"; cue = "Take shorter, quicker steps."
            case "heavy_bounce": label = "Heavy bounce"; cue = "Push forward, not up."
            case "run_lean": label = "Waist bend"; cue = "Run tall, lean from the ankles."
            case "short_pull": label = "Short pull"; cue = "Pull the handles past your hips."
            case "no_hinge": label = "No hip hinge"; cue = "Crunch down from the hips to load."
            case "squatting": label = "Squatting the pull"; cue = "Keep knees soft and hinge instead."
            case "short_reach": label = "Short reach"; cue = "Stretch tall at the top."
            case "too_upright": label = "Too upright"; cue = "Lean in to about 45 degrees."
            case "short_drive": label = "Short drive"; cue = "Drive your knees with powerful steps."
            case "arms_collapsed": label = "Arms collapse"; cue = "Lock your arms so your legs do the work."
            case "standing_tall": label = "Standing too tall"; cue = "Sit into a low, braced stance."
            case "arms_only": label = "Arms only"; cue = "Sit back and power the pull with your hips."
            case "pull_hunch": label = "Hunched pull"; cue = "Keep your chest up and sit back."
            case "chest_not_down": label = "Chest not down"; cue = "Drop all the way to the floor."
            case "slow_getup": label = "Slow get-up"; cue = "Snap up in one motion."
            case "short_jump": label = "Short jump"; cue = "Swing your arms and jump far."
            case "short_catch": label = "Short catch"; cue = "Slide in until your shins are vertical."
            case "early_arms": label = "Arms too early"; cue = "Legs first, then body, then arms."
            case "over_layback": label = "Too much layback"; cue = "Finish at 11 o'clock, not lying back."
            case "overreach": label = "Overreach"; cue = "Hinge from the hips, don't lunge forward."
            case "shoulder_tilt": label = "Shoulders tilt"; cue = "Grip hard and stay level."
            case "bent_arms": label = "Bent arms"; cue = "Let the weight hang on straight arms."
            case "knee_over_toe": label = "Knee past toes"; cue = "Take a longer step — knee over ankle."
            case "knee_no_touch": label = "Back knee high"; cue = "Sink until the back knee touches down."
            case "no_extension_throw": label = "Throw cut short"; cue = "Extend fully overhead on the throw."
            default: label = key.replacingOccurrences(of: "_", with: " ").capitalized; cue = "Clean this up for better reps."
            }
            return (key, label, cue)
        }
    }

    /// Skeleton sampled across the loop for drawing.
    static func frames(for exercise: Exercise, fault: String?, view: DemoView, count: Int = 48) -> [PoseFrame] {
        let total = duration(for: exercise) / speed(fault: fault)
        return (0..<count).map { index in
            let t = Double(index) / Double(count)
            let pose = pose(for: exercise, t: t, fault: fault, view: view)
            return PoseFrame(time: Float(t * total), points: Self.points(from: pose, view: view))
        }
    }

    // MARK: Rig → skeleton

    private static func points(from pose: DemoPose, view: DemoView) -> [JointPoint] {
        func dir(_ angle: Double) -> CGPoint {
            let r = angle * .pi / 180
            return CGPoint(x: sin(r), y: -cos(r))
        }
        func up(_ angle: Double) -> CGPoint {
            let r = angle * .pi / 180
            return CGPoint(x: sin(r), y: cos(r))
        }
        func add(_ a: CGPoint, _ b: CGPoint, _ len: Double) -> CGPoint {
            CGPoint(x: a.x + b.x * len, y: a.y + b.y * len)
        }

        let torsoLen = 0.26, upperArm = 0.13, foreArm = 0.13
        let thigh = 0.22, shin = 0.22, neckLen = 0.07, headLen = 0.09

        let hip = CGPoint(x: pose.hipX, y: pose.hipY)
        let shoulder = add(hip, up(pose.torso), torsoLen)
        let neck = add(shoulder, up(pose.torso), neckLen)
        let nose = add(neck, up(pose.torso + pose.headTilt), headLen)

        func limbJoints(origin: CGPoint, angle: Double, bend: Double, len1: Double, len2: Double) -> (CGPoint, CGPoint) {
            let joint = add(origin, dir(angle), len1)
            let end = add(joint, dir(angle + bend), len2)
            return (joint, end)
        }

        var pts = [CGPoint?](repeating: nil, count: 15)
        switch view {
        case .side:
            let nearDX = 0.016, farDX = -0.016
            let (nearElbow, nearWrist) = limbJoints(origin: shoulder, angle: pose.nearArm, bend: pose.nearBend, len1: upperArm, len2: foreArm)
            let farArmAngle = pose.farArm ?? pose.nearArm
            let farBendAngle = pose.farBend ?? pose.nearBend
            let (farElbow, farWrist) = limbJoints(origin: shoulder, angle: farArmAngle, bend: farBendAngle, len1: upperArm, len2: foreArm)
            let (nearKnee, nearAnkle) = limbJoints(origin: hip, angle: pose.nearLeg, bend: pose.nearKnee, len1: thigh, len2: shin)
            let farLegAngle = pose.farLeg ?? pose.nearLeg
            let farKneeAngle = pose.farKnee ?? pose.nearKnee
            let (farKneePt, farAnkle) = limbJoints(origin: hip, angle: farLegAngle, bend: farKneeAngle, len1: thigh, len2: shin)

            pts[J.nose] = nose
            pts[J.neck] = neck
            pts[J.leftShoulder] = shoulder.offsetted(farDX)
            pts[J.rightShoulder] = shoulder.offsetted(nearDX)
            pts[J.leftElbow] = farElbow.offsetted(farDX)
            pts[J.leftWrist] = farWrist.offsetted(farDX)
            pts[J.rightElbow] = nearElbow.offsetted(nearDX)
            pts[J.rightWrist] = nearWrist.offsetted(nearDX)
            pts[J.leftHip] = hip.offsetted(farDX / 2)
            pts[J.rightHip] = hip.offsetted(nearDX / 2)
            pts[J.root] = hip
            pts[J.leftKnee] = farKneePt.offsetted(farDX)
            pts[J.leftAnkle] = farAnkle.offsetted(farDX)
            pts[J.rightKnee] = nearKnee.offsetted(nearDX)
            pts[J.rightAnkle] = nearAnkle.offsetted(nearDX)

        case .front:
            let spreadS = 0.035, spreadH = 0.02
            func mirrored(_ angle: Double) -> Double { -angle }
            let (nearElbow, nearWrist) = limbJoints(origin: shoulder, angle: pose.nearArm, bend: pose.nearBend, len1: upperArm, len2: foreArm)
            let farArmAngle = mirrored(pose.farArm ?? pose.nearArm)
            let farBendAngle = -(pose.farBend ?? pose.nearBend)
            let (farElbow, farWrist) = limbJoints(origin: shoulder, angle: farArmAngle, bend: farBendAngle, len1: upperArm, len2: foreArm)
            let (nearKnee, nearAnkle) = limbJoints(origin: hip, angle: pose.nearLeg, bend: pose.nearKnee, len1: thigh, len2: shin)
            let farLegAngle = mirrored(pose.farLeg ?? pose.nearLeg)
            let farKneeAngle = -(pose.farKnee ?? pose.nearKnee)
            let (farKneePt, farAnkle) = limbJoints(origin: hip, angle: farLegAngle, bend: farKneeAngle, len1: thigh, len2: shin)

            let nearShoulder = CGPoint(x: shoulder.x + spreadS, y: shoulder.y + pose.shoulderTilt)
            let farShoulder = CGPoint(x: shoulder.x - spreadS, y: shoulder.y - pose.shoulderTilt)
            let nearHip = CGPoint(x: hip.x + spreadH, y: hip.y)
            let farHip = CGPoint(x: hip.x - spreadH, y: hip.y)
            let nearKneeOffset = shift(nearKnee, from: hip, to: nearHip)
            let nearAnkleOffset = shift(nearAnkle, from: hip, to: nearHip)
            let farKneeOffset = shift(farKneePt, from: hip, to: farHip)
            let farAnkleOffset = shift(farAnkle, from: hip, to: farHip)

            pts[J.nose] = nose
            pts[J.neck] = neck
            pts[J.leftShoulder] = farShoulder
            pts[J.rightShoulder] = nearShoulder
            pts[J.leftElbow] = farElbow
            pts[J.leftWrist] = farWrist
            pts[J.rightElbow] = nearElbow
            pts[J.rightWrist] = nearWrist
            pts[J.leftHip] = farHip
            pts[J.rightHip] = nearHip
            pts[J.root] = hip
            pts[J.leftKnee] = farKneeOffset
            pts[J.leftAnkle] = farAnkleOffset
            pts[J.rightKnee] = nearKneeOffset
            pts[J.rightAnkle] = nearAnkleOffset
        }

        return pts.map { point in
            guard let point else { return JointPoint() }
            return JointPoint(x: Float(point.x), y: Float(point.y), confidence: 1)
        }
    }

    private static func shift(_ p: CGPoint, from a: CGPoint, to b: CGPoint) -> CGPoint {
        CGPoint(x: p.x - a.x + b.x, y: p.y - a.y + b.y)
    }
    private static func wave(_ t: Double) -> Double {
        (1 - cos(2 * .pi * t)) / 2
    }

    private static func ramp(_ t: Double, _ start: Double, _ end: Double) -> Double {
        guard end > start else { return t >= end ? 1 : 0 }
        let u = max(0, min(1, (t - start) / (end - start)))
        return u * u * (3 - 2 * u)
    }

    private static func sample(keys: [(Double, DemoPose)], t: Double, slowGround: Bool = false) -> DemoPose {
        // For the slow get-up fault, stretch the ground phases and compress the air phase.
        var phases = keys.map { $0.0 }
        if slowGround {
            phases = keys.map { key -> Double in
                let phase = key.0
                let stretched = phase * 1.25
                let compressed = 0.55 + (phase - 0.55) * 0.65
                return phase < 0.55 ? stretched : compressed
            }
        }
        let time = t.truncatingRemainder(dividingBy: 1)
        for index in 0..<keys.count - 1 {
            let a = phases[index], b = phases[index + 1]
            if time >= a, time <= b {
                let span = max(b - a, 0.0001)
                let u = (time - a) / span
                return DemoPose.lerp(keys[index].1, keys[index + 1].1, u * u * (3 - 2 * u))
            }
        }
        return keys[keys.count - 1].1
    }
}

private extension CGPoint {
    func offsetted(_ dx: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y)
    }
}
