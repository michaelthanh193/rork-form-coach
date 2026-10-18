//
//  RepTracker.swift
//  FormCoach
//
//  Streams analyzed pose frames through a per-exercise state machine that
//  counts repetitions (or strokes / segments) and records the movement facts
//  needed to judge form.
//

import Foundation
import CoreGraphics

nonisolated final class RepTracker {
    private(set) var reps: [RepResult] = []
    private(set) var averageDown: Float = 0
    private(set) var averageUp: Float = 0
    private(set) var sawPerson = false
    /// Replaces the default tempo line when the exercise has a better summary (cadence, pacing).
    private(set) var summaryLabel: String?
    /// Checks that couldn't be judged reliably from this video (e.g. camera followed the athlete).
    private(set) var unverifiedChecks: Set<String> = []

    private let exercise: Exercise

    // Shared angle-rep state machine
    private var inRep = false
    private var repStart: Float = 0
    private var bottomTime: Float = 0
    private var bottomAngle: Double = 0
    private var startAngle: Double = 0
    private var startFacts: [String: Double] = [:]
    private var bottomFacts: [String: Double] = [:]
    private var peakFacts: [String: Double] = [:]
    private var driveElbowMin: Double = 180
    private var settleDeadline: Float?
    private var settleEndFacts: [String: Double] = [:]
    private var downSum: Float = 0
    private var upSum: Float = 0
    private var repDurations: Int = 0

    // Jumping jack state
    private var jjInUp = false
    private var jjStart: Float = 0
    private var jjTopY: Double = 0
    private var jjMaxAsym: Double = 0

    // Plank accumulation
    private var plankLineSamples: [Double] = []
    private var plankNeckSamples: [Double] = []
    private var plankStartTime: Float?

    // SkiErg stroke state
    private var skiInStroke = false
    private var skiStart: Float = 0
    private var skiMinH: Double = 9
    private var skiMinTime: Float = 0
    private var skiMaxTorso: Double = 0
    private var skiMinKnee: Double = 180
    private var skiTopElbow: Double = 0
    private var skiReachedBottom = false

    // Burpee broad jump state
    private var bbjDown = false
    private var bbjStart: Float = 0
    private var bbjMaxTorso: Double = 0
    private var bbjLowTime: Float = 0
    private var bbjDownHipX: [Double] = []
    private var bbjLegLength: Double = 0

    // Segment state (run, sled push, sled pull, farmers carry)
    private static let segmentLength: Float = 5
    private var segStart: Float?
    private var segLastTime: Float = 0
    private var segSamples: [[String: Double]] = []
    private var segSteps = 0
    private var stepSide: Int = 0
    private var totalSteps = 0
    private var totalSegmentTime: Float = 0

    init(exercise: Exercise) {
        self.exercise = exercise
    }

    func process(frame: PoseFrame) {
        if frame.points.contains(where: { $0.isValid }) { sawPerson = true }
        switch exercise {
        case .squat: trackAngleRep(frame, jointSet: .squat, completeAbove: 155)
        case .pushUp: trackAngleRep(frame, jointSet: .elbow, completeAbove: 150)
        case .lunge: trackAngleRep(frame, jointSet: .lunge, completeAbove: 155)
        case .bicepCurl: trackAngleRep(frame, jointSet: .curl, completeAbove: 150)
        case .wallBall: trackAngleRep(frame, jointSet: .wallBall, completeAbove: 158, settle: 0.5)
        case .sandbagLunge: trackAngleRep(frame, jointSet: .lunge, completeAbove: 150)
        case .row: trackAngleRep(frame, jointSet: .row, completeAbove: 145, settle: 0.4)
        case .jumpingJack: trackJumpingJack(frame)
        case .plank: accumulatePlank(frame)
        case .skiErg: trackSkiErg(frame)
        case .burpeeBroadJump: trackBurpeeBroadJump(frame)
        case .run, .sledPush, .sledPull, .farmersCarry: trackSegment(frame)
        }
    }

    func finalize(duration: Float) {
        if exercise == .plank, !plankLineSamples.isEmpty {
            finalizePlank(duration: duration)
        }
        if settleDeadline != nil {
            completeAngleRep(endTime: segLastTimeOr(duration))
        }
        if exercise.measure == .segments {
            closeSegment(isFinal: true)
            finalizeSegmentSummary()
        }
        if exercise == .burpeeBroadJump {
            finalizeBroadJumps()
        }
        if repDurations > 0 {
            averageDown /= Float(repDurations)
            averageUp /= Float(repDurations)
        }
        if exercise.measure == .strokes, repDurations > 0, !reps.isEmpty {
            // Row: start (finish) → bottom (catch) is the recovery; catch → finish is the drive.
            // SkiErg: start (hands high) → bottom (hands low) is the pull; the rest is recovery.
            let drive = exercise == .row ? averageUp : averageDown
            let recovery = exercise == .row ? averageDown : averageUp
            summaryLabel = String(format: "%.1f sec drive · %.1f sec recovery", drive, recovery)
        }
        if exercise == .burpeeBroadJump, !reps.isEmpty {
            let avg = reps.map { $0.end - $0.start }.reduce(0, +) / Float(reps.count)
            summaryLabel = String(format: "%.1f sec per burpee", avg)
        }
    }

    private func segLastTimeOr(_ fallback: Float) -> Float {
        segLastTime > 0 ? segLastTime : fallback
    }

    // MARK: - Angle-based reps (squat, push-up, lunges, curl, wall ball, row)

    private enum JointSet {
        case squat, elbow, lunge, curl, wallBall, row

        var range: ClosedRange<Double> {
            switch self {
            case .curl: 0...180
            default: 140...180
            }
        }
    }

    private func primaryAngle(_ frame: PoseFrame, _ set: JointSet) -> Double? {
        switch set {
        case .squat, .wallBall, .row:
            let l = frame.angle(J.leftHip, J.leftKnee, J.leftAnkle)
            let r = frame.angle(J.rightHip, J.rightKnee, J.rightAnkle)
            return PoseMath.average(l, r)
        case .elbow:
            let l = frame.angle(J.leftShoulder, J.leftElbow, J.leftWrist)
            let r = frame.angle(J.rightShoulder, J.rightElbow, J.rightWrist)
            return PoseMath.average(l, r)
        case .lunge:
            let l = frame.angle(J.leftHip, J.leftKnee, J.leftAnkle)
            let r = frame.angle(J.rightHip, J.rightKnee, J.rightAnkle)
            guard let lv = l, let rv = r else { return l ?? r }
            return min(lv, rv)
        case .curl:
            let l = frame.angle(J.leftShoulder, J.leftElbow, J.leftWrist)
            let r = frame.angle(J.rightShoulder, J.rightElbow, J.rightWrist)
            guard let lv = l, let rv = r else { return l ?? r }
            return min(lv, rv)
        }
    }

    private func captureFacts(_ frame: PoseFrame, _ set: JointSet) -> [String: Double] {
        var facts: [String: Double] = [:]
        if let torso = PoseMath.torsoAngle(frame) { facts["torso"] = torso }

        switch set {
        case .squat:
            facts["drift"] = PoseMath.worstKneeDrift(frame) ?? 0
        case .elbow:
            if let line = bodyLine(frame) { facts["line"] = line }
        case .lunge:
            facts["drift"] = PoseMath.worstKneeDrift(frame) ?? 0
            facts["kneeForward"] = PoseMath.kneeOverToe(frame) ?? 0
        case .curl:
            // Elbow drift: horizontal displacement of the working elbow from its shoulder.
            let options: [(Int, Int)] = [(J.leftShoulder, J.leftElbow), (J.rightShoulder, J.rightElbow)]
            var best: Double?
            for (s, e) in options {
                guard let shoulder = frame.pt(s), let elbow = frame.pt(e) else { continue }
                let drift = abs(elbow.x - shoulder.x) / max(abs(shoulder.y - elbow.y), 0.02)
                best = min(best ?? .greatestFiniteMagnitude, drift)
            }
            facts["elbowDrift"] = best ?? 0
        case .wallBall:
            facts["drift"] = PoseMath.worstKneeDrift(frame) ?? 0
            // Highest wrist relative to the nose (Vision y grows upward), in torso lengths.
            if let nose = frame.pt(J.nose) ?? frame.pt(J.neck), let torsoLen = PoseMath.torsoLength(frame) {
                let wrists = [frame.pt(J.leftWrist), frame.pt(J.rightWrist)].compactMap { $0 }
                if let top = wrists.map(\.y).max() {
                    facts["wristAboveHead"] = (top - nose.y) / torsoLen
                }
            }
        case .row:
            if let elbow = PoseMath.average(
                frame.angle(J.leftShoulder, J.leftElbow, J.leftWrist),
                frame.angle(J.rightShoulder, J.rightElbow, J.rightWrist)
            ) {
                facts["elbow"] = elbow
            }
        }
        return facts
    }

    private func bodyLine(_ frame: PoseFrame) -> Double? {
        guard let shoulder = frame.mid(J.leftShoulder, J.rightShoulder),
              let hip = frame.mid(J.leftHip, J.rightHip),
              let ankle = frame.mid(J.leftAnkle, J.rightAnkle) else { return nil }
        return PoseMath.angle(shoulder, hip, ankle)
    }

    private func trackAngleRep(_ frame: PoseFrame, jointSet: JointSet, completeAbove: Double, settle: Float = 0) {
        segLastTime = frame.time

        // Wall balls: after standing up, keep watching briefly so the throw's arm extension is captured.
        if let deadline = settleDeadline {
            let facts = captureFacts(frame, jointSet)
            mergePeaks(facts)
            for (key, value) in facts {
                settleEndFacts[key] = max(settleEndFacts[key] ?? value, value)
            }
            if frame.time >= deadline {
                completeAngleRep(endTime: frame.time)
            } else {
                return
            }
        }

        guard let angle = primaryAngle(frame, jointSet) else { return }

        if !inRep {
            guard jointSet.range.contains(angle) || angle >= completeAbove else { return }
            if angle >= completeAbove {
                inRep = true
                repStart = frame.time
                bottomTime = frame.time
                startAngle = angle
                bottomAngle = angle
                startFacts = captureFacts(frame, jointSet)
                bottomFacts = startFacts
                peakFacts = startFacts
                driveElbowMin = 180
            }
            return
        }

        let facts = captureFacts(frame, jointSet)
        mergePeaks(facts)

        if angle < bottomAngle {
            bottomAngle = angle
            bottomTime = frame.time
            bottomFacts = facts
            driveElbowMin = 180
        } else if jointSet == .row, angle < 120, let elbow = facts["elbow"] {
            // Drive phase with legs still bent: arms should stay straight.
            driveElbowMin = min(driveElbowMin, elbow)
        }

        if angle >= completeAbove {
            // Ignore jitter: a rep needs a real change in joint angle.
            guard bottomAngle < completeAbove - 25 else {
                repStart = frame.time
                bottomTime = frame.time
                startAngle = angle
                bottomAngle = angle
                startFacts = facts
                bottomFacts = facts
                peakFacts = facts
                return
            }
            settleEndFacts = facts
            if settle > 0 {
                settleDeadline = frame.time + settle
                inRep = false
                pendingSettleEnd = frame.time
            } else {
                completeAngleRep(endTime: frame.time)
                inRep = false
            }
        }
    }

    private var pendingSettleEnd: Float?

    private func mergePeaks(_ facts: [String: Double]) {
        for (key, value) in facts {
            peakFacts[key] = max(peakFacts[key] ?? value, value)
        }
    }

    private func completeAngleRep(endTime rawEnd: Float) {
        let endTime = pendingSettleEnd ?? rawEnd
        pendingSettleEnd = nil
        settleDeadline = nil

        let duration = max(endTime - repStart, 0.01)
        downSum += max(bottomTime - repStart, 0.01)
        upSum += max(endTime - bottomTime, 0.01)
        averageDown = downSum
        averageUp = upSum
        repDurations += 1

        var faults: [String] = []
        switch exercise {
        case .squat:
            if bottomAngle > 100 { faults.append("shallow_depth") }
            if bottomFacts["drift"] ?? 0 > 0.35 { faults.append("knee_drift") }
            if bottomFacts["torso"] ?? 0 > 50 { faults.append("torso_lean") }
            if duration > 7 { faults.append("slow_tempo") } else if duration < 0.8 { faults.append("fast_tempo") }
        case .pushUp:
            if bottomAngle > 105 { faults.append("shallow_depth") }
            if let line = bottomFacts["line"] {
                if line < 155 { faults.append("hip_sag") } else if line > 174 { faults.append("hip_pike") }
            }
            if duration < 0.7 { faults.append("fast_tempo") }
        case .lunge:
            if bottomAngle > 115 { faults.append("shallow_depth") }
            if bottomFacts["torso"] ?? 0 > 40 { faults.append("torso_lean") }
            if bottomFacts["kneeForward"] ?? 0 > 1.2 { faults.append("knee_over_toe") }
            if duration < 0.8 { faults.append("fast_tempo") }
        case .sandbagLunge:
            // HYROX standard: back knee touches the floor; the bag stays on the shoulders.
            if bottomAngle > 100 { faults.append("knee_no_touch") }
            if bottomFacts["torso"] ?? 0 > 30 { faults.append("torso_lean") }
            if bottomFacts["kneeForward"] ?? 0 > 1.2 { faults.append("knee_over_toe") }
        case .bicepCurl:
            if startAngle < 145 { faults.append("incomplete_extension") }
            if bottomAngle > 75 { faults.append("incomplete_contraction") }
            if bottomFacts["elbowDrift"] ?? 0 > 0.6 { faults.append("elbow_drift") }
            if let t0 = startFacts["torso"], let t1 = bottomFacts["torso"], abs(t1 - t0) > 12 {
                faults.append("body_swing")
            }
        case .wallBall:
            // HYROX standard: hip crease below the knee, ball released from full extension.
            if bottomAngle > 95 { faults.append("shallow_depth") }
            if let reach = peakFacts["wristAboveHead"], reach < 0.08 { faults.append("no_extension_throw") }
            if bottomFacts["drift"] ?? 0 > 0.35 { faults.append("knee_drift") }
            if bottomFacts["torso"] ?? 0 > 45 { faults.append("torso_lean") }
        case .row:
            if bottomAngle > 75 { faults.append("short_catch") }
            if driveElbowMin < 140 { faults.append("early_arms") }
            if settleEndFacts["torso"] ?? 0 > 40 { faults.append("over_layback") }
            if bottomFacts["torso"] ?? 0 > 45 { faults.append("overreach") }
        default:
            break
        }

        reps.append(RepResult(
            id: reps.count + 1,
            score: 0, // scored by the evaluator once all reps are known
            start: repStart,
            bottom: bottomTime,
            end: endTime,
            faults: faults
        ))
    }

    // MARK: - Jumping jack (arms overhead instead of a joint angle)

    private func trackJumpingJack(_ frame: PoseFrame) {
        guard let neckY = frame.pt(J.neck)?.y,
              let leftShoulderY = frame.pt(J.leftShoulder)?.y,
              let lw = frame.pt(J.leftWrist), let rw = frame.pt(J.rightWrist) else { return }

        let handUp = max(lw.y, rw.y) > leftShoulderY + 0.02
        let handDown = max(lw.y, rw.y) < neckY - 0.01

        if !jjInUp {
            if handUp {
                jjInUp = true
                jjStart = frame.time
                jjTopY = min(lw.y, rw.y)
                jjMaxAsym = 0
            }
            return
        }

        jjTopY = min(jjTopY, min(lw.y, rw.y))
        jjMaxAsym = max(jjMaxAsym, abs(Double(lw.y - rw.y)))

        if handDown {
            let duration = frame.time - jjStart
            downSum += duration / 2
            upSum += duration / 2
            averageDown = downSum
            averageUp = upSum
            repDurations += 1

            var faults: [String] = []
            if jjTopY < neckY + 0.03 { faults.append("incomplete_raise") }
            if jjMaxAsym > 0.08 { faults.append("arm_asymmetry") }
            if duration < 0.5 { faults.append("fast_tempo") }

            reps.append(RepResult(
                id: reps.count + 1,
                score: 0,
                start: jjStart,
                bottom: (jjStart + frame.time) / 2,
                end: frame.time,
                faults: faults
            ))
            jjInUp = false
        }
    }

    // MARK: - Plank (timed hold)

    private func accumulatePlank(_ frame: PoseFrame) {
        guard let shoulder = frame.mid(J.leftShoulder, J.rightShoulder),
              let hip = frame.mid(J.leftHip, J.rightHip),
              let ankle = frame.mid(J.leftAnkle, J.rightAnkle) else { return }
        plankLineSamples.append(PoseMath.angle(shoulder, hip, ankle))
        if plankStartTime == nil { plankStartTime = frame.time }
        if let nose = frame.pt(J.nose) {
            plankNeckSamples.append(nose.y - shoulder.y)
        }
    }

    private func finalizePlank(duration: Float) {
        let avgLine = plankLineSamples.reduce(0, +) / Double(plankLineSamples.count)
        var faults: [String] = []
        if avgLine < 160 { faults.append("hip_sag") }
        else if avgLine > 175 { faults.append("hip_pike") }
        if plankNeckSamples.count > 10 {
            let avgNeck = plankNeckSamples.reduce(0, +) / Double(plankNeckSamples.count)
            if abs(avgNeck) > 0.15 { faults.append("neck_crank") }
        }
        if duration < 20 { faults.append("short_hold") }

        reps.append(RepResult(
            id: 1,
            score: 0,
            start: plankStartTime ?? 0,
            bottom: duration / 2,
            end: duration,
            faults: faults
        ))
        repDurations = 1
        downSum = duration
        upSum = 0
        averageDown = downSum
        averageUp = upSum
    }

    // MARK: - SkiErg (hands travel from overhead to the thighs)

    private func trackSkiErg(_ frame: PoseFrame) {
        guard let hip = frame.mid(J.leftHip, J.rightHip) ?? frame.pt(J.root),
              let torsoLen = PoseMath.torsoLength(frame) else { return }
        let wrists = [frame.pt(J.leftWrist), frame.pt(J.rightWrist)].compactMap { $0 }
        guard !wrists.isEmpty else { return }
        // Hand height above the hips, in torso lengths: ~1 at the shoulders, ~0 at the hips.
        let h = (wrists.map(\.y).reduce(0, +) / Double(wrists.count) - hip.y) / torsoLen
        let torso = PoseMath.torsoAngle(frame)
        let knee = PoseMath.average(
            frame.angle(J.leftHip, J.leftKnee, J.leftAnkle),
            frame.angle(J.rightHip, J.rightKnee, J.rightAnkle)
        )
        let elbow = PoseMath.average(
            frame.angle(J.leftShoulder, J.leftElbow, J.leftWrist),
            frame.angle(J.rightShoulder, J.rightElbow, J.rightWrist)
        )

        if !skiInStroke {
            if h > 0.9 { beginSkiStroke(at: frame.time, h: h, elbow: elbow) }
            return
        }

        if !skiReachedBottom, h > 0.8, let elbow { skiTopElbow = max(skiTopElbow, elbow) }
        if h < skiMinH {
            skiMinH = h
            skiMinTime = frame.time
        }
        if let torso { skiMaxTorso = max(skiMaxTorso, torso) }
        if let knee { skiMinKnee = min(skiMinKnee, knee) }
        if h < 0.45 { skiReachedBottom = true }

        if skiReachedBottom, h > 0.9 {
            var faults: [String] = []
            if skiMinH > 0.1 { faults.append("short_pull") }
            if skiMaxTorso < 20 { faults.append("no_hinge") }
            if skiMinKnee < 105 { faults.append("squatting") }
            if skiTopElbow > 0, skiTopElbow < 145 { faults.append("short_reach") }

            downSum += max(skiMinTime - skiStart, 0.01)
            upSum += max(frame.time - skiMinTime, 0.01)
            averageDown = downSum
            averageUp = upSum
            repDurations += 1

            reps.append(RepResult(
                id: reps.count + 1,
                score: 0,
                start: skiStart,
                bottom: skiMinTime,
                end: frame.time,
                faults: faults
            ))
            beginSkiStroke(at: frame.time, h: h, elbow: elbow)
        }
    }

    private func beginSkiStroke(at time: Float, h: Double, elbow: Double?) {
        skiInStroke = true
        skiStart = time
        skiMinH = h
        skiMinTime = time
        skiMaxTorso = 0
        skiMinKnee = 180
        skiTopElbow = elbow ?? 0
        skiReachedBottom = false
    }

    // MARK: - Burpee broad jump (torso goes horizontal, then upright, then jump)

    private func trackBurpeeBroadJump(_ frame: PoseFrame) {
        guard let torso = PoseMath.torsoAngle(frame) else { return }
        if let leg = PoseMath.legLength(frame) { bbjLegLength = max(bbjLegLength, leg) }

        if !bbjDown {
            if torso > 60 {
                bbjDown = true
                bbjStart = frame.time
                bbjMaxTorso = torso
                bbjLowTime = frame.time
                if let hip = frame.mid(J.leftHip, J.rightHip) ?? frame.pt(J.root) {
                    bbjDownHipX.append(hip.x)
                } else {
                    bbjDownHipX.append(.nan)
                }
            }
            return
        }

        if torso >= bbjMaxTorso {
            bbjMaxTorso = torso
            bbjLowTime = frame.time
        }

        if torso < 35 {
            var faults: [String] = []
            if bbjMaxTorso < 72 { faults.append("chest_not_down") }
            if frame.time - bbjLowTime > 2.2 { faults.append("slow_getup") }

            downSum += max(bbjLowTime - bbjStart, 0.01)
            upSum += max(frame.time - bbjLowTime, 0.01)
            averageDown = downSum
            averageUp = upSum
            repDurations += 1

            reps.append(RepResult(
                id: reps.count + 1,
                score: 0,
                start: bbjStart,
                bottom: bbjLowTime,
                end: frame.time,
                faults: faults
            ))
            bbjDown = false
        }
    }

    /// Jump distance = hip travel between consecutive burpees, judged once all reps are known.
    private func finalizeBroadJumps() {
        guard bbjLegLength > 0.02, bbjDownHipX.count >= 2, !reps.isEmpty else {
            unverifiedChecks.insert("short_jump")
            return
        }
        var jumps: [Double] = []
        for index in 1..<bbjDownHipX.count {
            let a = bbjDownHipX[index - 1], b = bbjDownHipX[index]
            jumps.append(a.isNaN || b.isNaN ? .nan : abs(b - a) / bbjLegLength)
        }
        let measured = jumps.filter { !$0.isNaN }.sorted()
        // If the camera followed the athlete, hips barely move in frame — the check can't be trusted.
        guard let median = measured.isEmpty ? nil : measured[measured.count / 2], median > 0.15 else {
            unverifiedChecks.insert("short_jump")
            return
        }
        for (index, jump) in jumps.enumerated() where index < reps.count && !jump.isNaN && jump < 0.5 {
            reps[index].faults.append("short_jump")
        }
    }

    // MARK: - Segments (run, sled push, sled pull, farmers carry)

    private func trackSegment(_ frame: PoseFrame) {
        guard frame.points.filter(\.isValid).count >= 6 else { return }
        if segStart == nil {
            segStart = frame.time
            segSteps = 0
        }
        segLastTime = frame.time
        segSamples.append(segmentFacts(frame))
        if exercise == .run { countStep(frame) }

        if let start = segStart, frame.time - start >= Self.segmentLength {
            closeSegment(isFinal: false)
        }
    }

    private func segmentFacts(_ frame: PoseFrame) -> [String: Double] {
        var facts: [String: Double] = [:]
        if let torso = PoseMath.torsoAngle(frame) { facts["torso"] = torso }
        let lKnee = frame.angle(J.leftHip, J.leftKnee, J.leftAnkle)
        let rKnee = frame.angle(J.rightHip, J.rightKnee, J.rightAnkle)
        if let knee = [lKnee, rKnee].compactMap({ $0 }).min() { facts["kneeMin"] = knee }
        if let knee = PoseMath.average(lKnee, rKnee) { facts["kneeAvg"] = knee }
        if let elbow = PoseMath.average(
            frame.angle(J.leftShoulder, J.leftElbow, J.leftWrist),
            frame.angle(J.rightShoulder, J.rightElbow, J.rightWrist)
        ) {
            facts["elbow"] = elbow
        }
        if let hipAngle = PoseMath.average(
            frame.angle(J.leftShoulder, J.leftHip, J.leftKnee),
            frame.angle(J.rightShoulder, J.rightHip, J.rightKnee)
        ) {
            facts["hipAngle"] = hipAngle
        }
        if let ls = frame.pt(J.leftShoulder), let rs = frame.pt(J.rightShoulder), let torsoLen = PoseMath.torsoLength(frame) {
            facts["tilt"] = abs(ls.y - rs.y) / torsoLen
        }
        if let leg = PoseMath.legLength(frame) {
            facts["leg"] = leg
            if let hip = frame.mid(J.leftHip, J.rightHip) {
                facts["hipY"] = hip.y
                // Overstride: how far the lower (landing) foot sits ahead of/behind the hips.
                if let la = frame.pt(J.leftAnkle), let ra = frame.pt(J.rightAnkle) {
                    let landing = la.y < ra.y ? la : ra
                    if abs(la.y - ra.y) > 0.01 {
                        facts["stride"] = abs(landing.x - hip.x) / leg
                    }
                }
            }
        }
        return facts
    }

    /// Counts steps as the feet swap which one is in front (with hysteresis against jitter).
    private func countStep(_ frame: PoseFrame) {
        guard let la = frame.pt(J.leftAnkle), let ra = frame.pt(J.rightAnkle) else { return }
        let diff = la.x - ra.x
        let side = diff > 0.02 ? 1 : (diff < -0.02 ? -1 : 0)
        guard side != 0 else { return }
        if stepSide != 0, side != stepSide {
            segSteps += 1
            totalSteps += 1
        }
        stepSide = side
    }

    private func closeSegment(isFinal: Bool) {
        guard let start = segStart else { return }
        let length = segLastTime - start
        defer {
            segStart = nil
            segSamples = []
        }
        // A trailing scrap under 2 seconds isn't enough to judge — unless it's all we have.
        guard segSamples.count >= 5, length >= 2 || (isFinal && reps.isEmpty && length >= 1) else { return }
        totalSegmentTime += length

        func avg(_ key: String) -> Double? {
            let values = segSamples.compactMap { $0[key] }
            guard values.count >= 4 else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        func values(_ key: String) -> [Double] { segSamples.compactMap { $0[key] } }

        var faults: [String] = []
        switch exercise {
        case .farmersCarry:
            if let torso = avg("torso"), torso > 15 { faults.append("torso_lean") }
            if let tilt = avg("tilt"), tilt > 0.12 { faults.append("shoulder_tilt") }
            if let elbow = avg("elbow"), elbow < 155 { faults.append("bent_arms") }
        case .sledPush:
            if let torso = avg("torso"), torso < 30 { faults.append("too_upright") }
            let knees = values("kneeMin")
            if knees.count >= 4, let deepest = knees.min(), deepest > 135 { faults.append("short_drive") }
            if let elbow = avg("elbow"), elbow < 110 { faults.append("arms_collapsed") }
        case .sledPull:
            if let knee = avg("kneeAvg"), knee > 165 { faults.append("standing_tall") }
            let hips = values("hipAngle")
            if hips.count >= 6, PoseMath.standardDeviation(hips) < 6 { faults.append("arms_only") }
            if let torso = avg("torso"), torso > 50 { faults.append("pull_hunch") }
        case .run:
            let strides = values("stride").sorted()
            if strides.count >= 6 {
                let p80 = strides[Int(Double(strides.count - 1) * 0.8)]
                if p80 > 0.5 { faults.append("overstriding") }
            }
            if length >= 3 {
                let cadence = Double(segSteps) / Double(length) * 60
                if segSteps >= 2, cadence < 155 { faults.append("low_cadence") }
            }
            let hipYs = values("hipY")
            if hipYs.count >= 6, let leg = avg("leg"), leg > 0.02,
               let hi = hipYs.max(), let lo = hipYs.min(), (hi - lo) / leg > 0.14 {
                faults.append("heavy_bounce")
            }
            if let torso = avg("torso"), torso > 20 { faults.append("run_lean") }
        default:
            break
        }

        reps.append(RepResult(
            id: reps.count + 1,
            score: 0,
            start: start,
            bottom: start + length / 2,
            end: segLastTime,
            faults: faults
        ))
    }

    private func finalizeSegmentSummary() {
        guard totalSegmentTime > 0 else { return }
        if exercise == .run, totalSteps >= 4 {
            let cadence = Int((Double(totalSteps) / Double(totalSegmentTime) * 60).rounded())
            summaryLabel = "\(cadence) steps/min"
        } else {
            summaryLabel = "Worked for \(Int(totalSegmentTime.rounded())) sec"
        }
    }
}

nonisolated extension PoseMath {
    /// Average of optional values, ignoring nil.
    static func average(_ values: Double?...) -> Double? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }

    /// Neck-to-hip distance, used to normalize heights across camera distances.
    static func torsoLength(_ frame: PoseFrame) -> Double? {
        guard let neck = frame.pt(J.neck),
              let hip = frame.mid(J.leftHip, J.rightHip) ?? frame.pt(J.root) else { return nil }
        let length = sqrt(pow(neck.x - hip.x, 2) + pow(neck.y - hip.y, 2))
        return length > 0.02 ? length : nil
    }

    /// Longest visible hip-to-ankle distance.
    static func legLength(_ frame: PoseFrame) -> Double? {
        let legs = [(J.leftHip, J.leftAnkle), (J.rightHip, J.rightAnkle)]
        let lengths = legs.compactMap { h, a -> Double? in
            guard let hip = frame.pt(h), let ankle = frame.pt(a) else { return nil }
            return sqrt(pow(hip.x - ankle.x, 2) + pow(hip.y - ankle.y, 2))
        }
        guard let longest = lengths.max(), longest > 0.02 else { return nil }
        return longest
    }

    /// How far each knee drifts from the hip-ankle line, as a fraction of leg length.
    static func worstKneeDrift(_ frame: PoseFrame) -> Double? {
        var worst: Double?
        let legs = [(J.leftHip, J.leftKnee, J.leftAnkle), (J.rightHip, J.rightKnee, J.rightAnkle)]
        for (h, k, a) in legs {
            guard let hip = frame.pt(h), let knee = frame.pt(k), let ankle = frame.pt(a) else { continue }
            let legLength = sqrt(pow(hip.x - ankle.x, 2) + pow(hip.y - ankle.y, 2))
            guard legLength > 0.02 else { continue }
            let drift = abs(knee.x - ankle.x) / legLength
            worst = max(worst ?? 0, drift)
        }
        return worst
    }

    /// How far the front knee travels past the ankle, relative to shin length.
    static func kneeOverToe(_ frame: PoseFrame) -> Double? {
        let legs = [(J.leftHip, J.leftKnee, J.leftAnkle), (J.rightHip, J.rightKnee, J.rightAnkle)]
        var worst: Double?
        for (_, k, a) in legs {
            guard let knee = frame.pt(k), let ankle = frame.pt(a) else { continue }
            let shin = sqrt(pow(knee.x - ankle.x, 2) + pow(knee.y - ankle.y, 2))
            guard shin > 0.02 else { continue }
            let forward = abs(knee.x - ankle.x) / shin
            worst = max(worst ?? 0, forward)
        }
        return worst
    }
}
