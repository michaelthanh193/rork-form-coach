//
//  FormEvaluator.swift
//  FormCoach
//
//  Turns raw rep data into a coach-like report: scores, strengths, fixes,
//  and flagged moments for skeleton playback.
//

import Foundation

nonisolated enum FormEvaluator {

    /// Coaching copy for one form check.
    private struct Check {
        /// Points removed from a rep's score when this fault appears.
        let deduction: Int
        /// What a clean version sounds like as a strength.
        let strength: String
        /// The specific fix. The rep/segment label is spliced in by the caller.
        let fix: String
        /// Short caption shown during skeleton playback.
        let warning: String
    }

    private static let checks: [String: Check] = [
        // Strength basics
        "shallow_depth": Check(deduction: 22, strength: "Full depth on every rep", fix: "go deeper — thighs to parallel at the bottom", warning: "shallow rep — go deeper"),
        "knee_drift": Check(deduction: 15, strength: "Knees tracked cleanly over your toes", fix: "knees drifted inward — press them out over your toes", warning: "knees caving in — press out"),
        "torso_lean": Check(deduction: 12, strength: "Torso stayed tall and braced", fix: "chest fell forward — brace your core and stay tall", warning: "chest falling — brace your core"),
        "slow_tempo": Check(deduction: 6, strength: "Consistent tempo throughout", fix: "rep was a grind — drive up with intent", warning: "grinding rep — drive up"),
        "fast_tempo": Check(deduction: 8, strength: "Consistent tempo throughout", fix: "rep rushed — control the descent for 2 seconds", warning: "rushed rep — slow it down"),
        "hip_sag": Check(deduction: 18, strength: "Hips held a straight line", fix: "hips sagged — squeeze your glutes and brace", warning: "hips sagging — squeeze glutes"),
        "hip_pike": Check(deduction: 12, strength: "Hips held a straight line", fix: "hips piked up — lower them into a straight line", warning: "hips piked — straight line"),
        "knee_over_toe": Check(deduction: 12, strength: "Front knee tracked over your foot", fix: "knee traveled past your toes — take a longer step", warning: "knee past toes — longer step"),
        "incomplete_extension": Check(deduction: 12, strength: "Full range of motion every rep", fix: "didn't fully extend — straighten at the bottom", warning: "not fully extended"),
        "incomplete_contraction": Check(deduction: 10, strength: "Strong peak contraction every rep", fix: "didn't reach the top — squeeze at the peak", warning: "squeeze at the top"),
        "elbow_drift": Check(deduction: 12, strength: "Elbows stayed pinned in place", fix: "elbow drifted forward — pin it to your ribs", warning: "elbow drifting — pin it"),
        "body_swing": Check(deduction: 12, strength: "Strict reps — no momentum cheating", fix: "swung with momentum — keep your torso still", warning: "swinging — stay strict"),
        "incomplete_raise": Check(deduction: 10, strength: "Full arm raise on every rep", fix: "arms didn't reach overhead — raise fully", warning: "raise fully overhead"),
        "arm_asymmetry": Check(deduction: 10, strength: "Perfectly symmetrical movement", fix: "arms uneven — move both hands together", warning: "keep your hands even"),
        "neck_crank": Check(deduction: 8, strength: "Neutral neck through the hold", fix: "neck craned — keep it in line with your spine", warning: "keep your neck neutral"),
        "short_hold": Check(deduction: 0, strength: "Solid hold time", fix: "short hold — build toward 30 seconds", warning: "hold it longer next time"),

        // HYROX — wall balls
        "no_extension_throw": Check(deduction: 14, strength: "Full extension into every throw", fix: "arms didn't finish overhead — drive through your legs and extend fully on the throw", warning: "finish the throw overhead"),
        // HYROX — burpee broad jumps
        "chest_not_down": Check(deduction: 20, strength: "Chest to the floor on every burpee", fix: "chest didn't reach the floor — drop all the way down or it's a no-rep", warning: "chest to the floor"),
        "slow_getup": Check(deduction: 8, strength: "Quick, efficient get-ups", fix: "slow off the floor — snap your feet under your hips and stand in one move", warning: "get up faster"),
        "short_jump": Check(deduction: 12, strength: "Strong, far broad jumps", fix: "short jump — swing your arms and push your hips forward to cover more ground", warning: "jump further"),
        // HYROX — sandbag lunges
        "knee_no_touch": Check(deduction: 20, strength: "Back knee touched down every lunge", fix: "back knee didn't reach the floor — sink lower until it touches the ground", warning: "knee to the floor"),
        // HYROX — farmers carry
        "shoulder_tilt": Check(deduction: 12, strength: "Shoulders stayed level under load", fix: "shoulders tilted — grip hard and keep both sides even", warning: "level your shoulders"),
        "bent_arms": Check(deduction: 10, strength: "Arms long and relaxed under the handles", fix: "arms bent — let the weight hang on straight arms", warning: "straighten your arms"),
        // HYROX — sled push
        "too_upright": Check(deduction: 16, strength: "Strong forward lean into the sled", fix: "too upright — lean in to about 45° so your legs move the sled, not your arms", warning: "lean into the sled"),
        "short_drive": Check(deduction: 12, strength: "Powerful knee drive every step", fix: "short steps — drive your knees and push off the balls of your feet", warning: "drive your knees"),
        "arms_collapsed": Check(deduction: 10, strength: "Arms locked — leg drive went straight into the sled", fix: "arms collapsed — lock them so your leg drive reaches the sled", warning: "lock your arms"),
        // HYROX — sled pull
        "standing_tall": Check(deduction: 14, strength: "Low, athletic stance on the rope", fix: "standing too tall — sit into a low stance and brace your feet", warning: "get lower"),
        "arms_only": Check(deduction: 12, strength: "Hips powered every pull", fix: "pulling with arms only — sit back and use your hips on each pull", warning: "use your hips"),
        "pull_hunch": Check(deduction: 10, strength: "Chest up through the pull", fix: "hunched over the rope — keep your chest up and sit back", warning: "chest up"),
        // HYROX — run
        "overstriding": Check(deduction: 14, strength: "Feet landing under your hips", fix: "overstriding — land with your foot under your hips, not out in front", warning: "land under your hips"),
        "low_cadence": Check(deduction: 10, strength: "Quick, light cadence", fix: "low cadence — take shorter, quicker steps (aim for 170+ per minute)", warning: "quicker steps"),
        "heavy_bounce": Check(deduction: 8, strength: "Smooth, efficient stride", fix: "bouncing too much — push forward, not up", warning: "less bounce"),
        "run_lean": Check(deduction: 8, strength: "Tall running posture", fix: "bending at the waist — run tall and lean from the ankles", warning: "run tall"),
        // HYROX — SkiErg
        "short_pull": Check(deduction: 14, strength: "Full pull past the hips on every stroke", fix: "short pull — finish with your hands past your hips", warning: "pull past your hips"),
        "no_hinge": Check(deduction: 12, strength: "Strong hip hinge powering each stroke", fix: "no hip hinge — crunch your torso down to load your core", warning: "hinge at the hips"),
        "squatting": Check(deduction: 10, strength: "Hinged the stroke instead of squatting it", fix: "squatting the pull — keep knees soft and hinge instead", warning: "hinge, don't squat"),
        "short_reach": Check(deduction: 8, strength: "Tall reach at the top", fix: "short reach — stretch tall with straight arms at the top", warning: "reach tall"),
        // HYROX — rowing
        "short_catch": Check(deduction: 14, strength: "Full compression at the catch", fix: "short catch — slide in until your shins are vertical before driving", warning: "compress at the catch"),
        "early_arms": Check(deduction: 14, strength: "Clean legs–body–arms sequence", fix: "arms bent too early — push with legs first, then swing, then pull", warning: "legs before arms"),
        "over_layback": Check(deduction: 10, strength: "Controlled finish position", fix: "leaning back too far — finish at 11 o'clock, not lying down", warning: "less layback"),
        "overreach": Check(deduction: 10, strength: "Strong, stable catch posture", fix: "overreaching at the catch — hinge from the hips, don't lunge forward", warning: "don't overreach"),
    ]

    /// Exercise-specific wording where the generic fix doesn't fit the standard.
    private static let fixOverrides: [String: String] = [
        "wallBall.shallow_depth": "squat didn't break parallel — at HYROX that's a no-rep. Sit your hips below your knees",
        "wallBall.torso_lean": "chest dropped in the squat — keep the ball tight to your chest and stay upright",
        "sandbagLunge.torso_lean": "folding forward under the bag — brace and keep your chest proud",
        "farmersCarry.torso_lean": "leaning while you walk — stack your ribs over your hips and stand tall",
    ]

    /// The checks each exercise is judged on. Strengths only come from these.
    private static func checkKeys(for exercise: Exercise) -> [String] {
        switch exercise {
        case .squat: ["shallow_depth", "knee_drift", "torso_lean", "slow_tempo", "fast_tempo"]
        case .pushUp: ["shallow_depth", "hip_sag", "hip_pike", "fast_tempo"]
        case .lunge: ["shallow_depth", "torso_lean", "knee_over_toe", "fast_tempo"]
        case .plank: ["hip_sag", "hip_pike", "neck_crank", "short_hold"]
        case .jumpingJack: ["incomplete_raise", "arm_asymmetry", "fast_tempo"]
        case .bicepCurl: ["incomplete_extension", "incomplete_contraction", "elbow_drift", "body_swing"]
        case .run: ["overstriding", "low_cadence", "heavy_bounce", "run_lean"]
        case .skiErg: ["short_pull", "no_hinge", "squatting", "short_reach"]
        case .sledPush: ["too_upright", "short_drive", "arms_collapsed"]
        case .sledPull: ["standing_tall", "arms_only", "pull_hunch"]
        case .burpeeBroadJump: ["chest_not_down", "slow_getup", "short_jump"]
        case .row: ["short_catch", "early_arms", "over_layback", "overreach"]
        case .farmersCarry: ["torso_lean", "shoulder_tilt", "bent_arms"]
        case .sandbagLunge: ["knee_no_touch", "torso_lean", "knee_over_toe"]
        case .wallBall: ["shallow_depth", "no_extension_throw", "knee_drift", "torso_lean"]
        }
    }

    /// Fault keys that describe one shared aspect, so a clean set yields one strength line.
    private static let sharedAspects: [Set<String>] = [
        ["slow_tempo", "fast_tempo"],
        ["hip_sag", "hip_pike"],
    ]

    static func evaluate(
        exercise: Exercise,
        reps: [RepResult],
        duration: Float,
        videoAspect: Float,
        frames: [PoseFrame],
        tempoLabel: String,
        unverifiedChecks: Set<String> = [],
        cameraMotion: CameraMotion? = nil
    ) -> WorkoutAnalysis {
        var unverified = unverifiedChecks
        if cameraMotion?.isUnstable == true, cameraMotion?.corrected != true {
            // Checks that judge distances on screen can't survive uncorrected
            // camera movement — skip them rather than coach from wrong numbers.
            // Corrected footage was already steadied, so its checks stand.
            unverified.formUnion(Self.distanceBasedChecks)
        }

        let scored = reps.enumerated().map { index, rep -> RepResult in
            let penalty = rep.faults.reduce(0) { $0 + (checks[$1]?.deduction ?? 8) }
            return RepResult(
                id: index + 1,
                score: max(35, min(100, 100 - penalty)),
                start: rep.start,
                bottom: rep.bottom,
                end: rep.end,
                faults: rep.faults
            )
        }

        let overallScore = scored.isEmpty ? 0 : Int((Double(scored.map(\.score).reduce(0, +)) / Double(scored.count)).rounded())

        return WorkoutAnalysis(
            exercise: exercise,
            duration: duration,
            videoAspect: videoAspect,
            overallScore: overallScore,
            reps: scored,
            strengths: strengths(for: exercise, reps: scored, unverified: unverified),
            fixes: fixes(for: exercise, reps: scored),
            frames: frames,
            flags: flags(reps: scored, exercise: exercise),
            tempoLabel: tempoLabel,
            cameraMotion: cameraMotion
        )
    }

    /// Fault keys measured as distances on screen. A moving camera inflates or
    /// deflates them, so they are skipped on unstable footage.
    private static let distanceBasedChecks: Set<String> = [
        "short_jump", "heavy_bounce", "overstriding", "short_drive",
    ]

    /// The fault behind a flagged moment. Older reports didn't store it, so it's
    /// recovered from the caption, which always ends with the check's warning.
    static func faultKey(for moment: Moment) -> String? {
        if let fault = moment.fault { return fault }
        return checks
            .filter { moment.message.hasSuffix($0.value.warning) }
            .max { $0.value.warning.count < $1.value.warning.count }?
            .key
    }

    /// Plain-language names of this exercise's distance-based checks, used by the
    /// report banner when they had to be skipped.
    static func distanceCheckLabels(for exercise: Exercise) -> [String] {
        let names: [String: String] = [
            "short_jump": "jump distance",
            "heavy_bounce": "running bounce",
            "overstriding": "stride length",
            "short_drive": "knee drive",
        ]
        return checkKeys(for: exercise)
            .filter { distanceBasedChecks.contains($0) }
            .compactMap { names[$0] }
    }

    /// Re-judges a saved analysis under the current sensitivity. When the camera
    /// moved beyond the threshold and the footage wasn't corrected, distance-based
    /// faults are stripped and scores, strengths and fixes recomputed; otherwise
    /// the analysis comes back unchanged.
    static func resolve(_ analysis: WorkoutAnalysis, sensitivity: MotionSensitivity) -> WorkoutAnalysis {
        guard let motion = analysis.cameraMotion,
              motion.isUnstable(threshold: sensitivity.threshold),
              motion.corrected != true else { return analysis }

        var changed = false
        let stripped = analysis.reps.map { rep -> RepResult in
            let kept = rep.faults.filter { !distanceBasedChecks.contains($0) }
            guard kept.count != rep.faults.count else { return rep }
            changed = true
            let penalty = kept.reduce(0) { $0 + (checks[$1]?.deduction ?? 8) }
            return RepResult(
                id: rep.id,
                score: max(35, min(100, 100 - penalty)),
                start: rep.start,
                bottom: rep.bottom,
                end: rep.end,
                faults: kept
            )
        }
        guard changed else { return analysis }

        let overallScore = stripped.isEmpty
            ? 0
            : Int((Double(stripped.map(\.score).reduce(0, +)) / Double(stripped.count)).rounded())

        return WorkoutAnalysis(
            exercise: analysis.exercise,
            duration: analysis.duration,
            videoAspect: analysis.videoAspect,
            overallScore: overallScore,
            reps: stripped,
            strengths: strengths(for: analysis.exercise, reps: stripped, unverified: distanceBasedChecks),
            fixes: fixes(for: analysis.exercise, reps: stripped),
            frames: analysis.frames,
            flags: flags(reps: stripped, exercise: analysis.exercise),
            tempoLabel: analysis.tempoLabel,
            cameraMotion: motion
        )
    }

    private static func strengths(for exercise: Exercise, reps: [RepResult], unverified: Set<String>) -> [FeedbackItem] {
        guard !reps.isEmpty else { return [] }

        // Build ordered aspect groups from this exercise's checks.
        var groups: [Set<String>] = []
        for key in checkKeys(for: exercise) where !unverified.contains(key) {
            if groups.contains(where: { $0.contains(key) }) { continue }
            let shared = sharedAspects.first(where: { $0.contains(key) }) ?? [key]
            groups.append(shared)
        }

        var items: [FeedbackItem] = []
        for keys in groups {
            let clean = reps.filter { Set($0.faults).isDisjoint(with: keys) }
            guard Double(clean.count) / Double(reps.count) >= 0.75, clean.count == reps.count || reps.count >= 3 else { continue }
            let ordered = checkKeys(for: exercise).filter { keys.contains($0) }
            guard let key = ordered.first, let line = checks[key]?.strength else { continue }
            if !items.contains(where: { $0.title == line }) {
                items.append(FeedbackItem(id: key, title: line))
            }
        }
        return Array(items.prefix(3))
    }

    private static func fixes(for exercise: Exercise, reps: [RepResult]) -> [FeedbackItem] {
        var counts: [String: Int] = [:]
        var firstRepWithFault: [String: RepResult] = [:]
        for rep in reps {
            for fault in rep.faults {
                counts[fault, default: 0] += 1
                if firstRepWithFault[fault] == nil { firstRepWithFault[fault] = rep }
            }
        }

        let order = checkKeys(for: exercise)
        let sorted = counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99)
        }
        return sorted.prefix(3).compactMap { fault, count in
            guard let line = fixOverrides["\(exercise.rawValue).\(fault)"] ?? checks[fault]?.fix else { return nil }
            let title: String
            if exercise.isHold {
                title = line.capitalizedFirst
            } else if let rep = firstRepWithFault[fault] {
                let label = unitLabel(for: exercise, rep: rep)
                let extra = count > 1 ? " (+\(count - 1) more)" : ""
                title = "\(label)\(extra): \(line)"
            } else {
                title = line.capitalizedFirst
            }
            return FeedbackItem(id: fault, title: title)
        }
    }

    /// "Rep 7", "Stroke 12", or "Segment 3 at 0:10" — segments carry a timestamp for long race clips.
    private static func unitLabel(for exercise: Exercise, rep: RepResult) -> String {
        let base = "\(exercise.unitSingular.capitalizedFirst) \(rep.id)"
        guard exercise.measure == .segments else { return base }
        let seconds = Int(rep.start.rounded())
        return "\(base) at \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private static func flags(reps: [RepResult], exercise: Exercise) -> [Moment] {
        var moments: [Moment] = []
        for rep in reps {
            for fault in rep.faults where checks[fault]?.deduction ?? 0 > 0 {
                let prefix = exercise.isHold ? "Hold — " : "\(exercise.unitSingular.capitalizedFirst) \(rep.id) — "
                moments.append(Moment(
                    time: rep.bottom,
                    message: prefix + (checks[fault]?.warning ?? "check your form"),
                    fault: fault
                ))
            }
        }
        return moments.sorted { $0.time < $1.time }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
