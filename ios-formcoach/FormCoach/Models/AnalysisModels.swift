//
//  AnalysisModels.swift
//  FormCoach
//
//  Data produced by the on-device analysis pipeline.
//

import Foundation
import CoreGraphics

/// Indexes into a `PoseFrame`'s point array, matching `PoseAnalyzer.jointOrder`.
enum J {
    static let nose = 0
    static let neck = 1
    static let leftShoulder = 2
    static let rightShoulder = 3
    static let leftElbow = 4
    static let rightElbow = 5
    static let leftWrist = 6
    static let rightWrist = 7
    static let leftHip = 8
    static let rightHip = 9
    static let leftKnee = 10
    static let rightKnee = 11
    static let leftAnkle = 12
    static let rightAnkle = 13
    static let root = 14
}

/// One tracked joint, in normalized image coordinates (origin bottom-left, like Vision).
nonisolated struct JointPoint: Codable, Sendable {
    var x: Float = 0
    var y: Float = 0
    var confidence: Float = 0

    var isValid: Bool { confidence > 0.3 }
}

/// A single analyzed video frame with the tracked skeleton.
nonisolated struct PoseFrame: Codable, Sendable {
    var time: Float
    var points: [JointPoint]

    func pt(_ index: Int) -> CGPoint? {
        guard points.indices.contains(index), points[index].isValid else { return nil }
        return CGPoint(x: Double(points[index].x), y: Double(points[index].y))
    }

    func mid(_ a: Int, _ b: Int) -> CGPoint? {
        guard let pa = pt(a), let pb = pt(b) else { return nil }
        return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    }

    /// Joint angle in degrees at vertex `b`.
    func angle(_ a: Int, _ b: Int, _ c: Int) -> Double? {
        guard let pa = pt(a), let pb = pt(b), let pc = pt(c) else { return nil }
        return PoseMath.angle(pa, pb, pc)
    }

    /// A copy with every joint moved by the given normalized offset — used to
    /// subtract camera drift so the person's own movement is what remains.
    func offsetBy(dx: Float, dy: Float) -> PoseFrame {
        var copy = self
        copy.points = points.map { JointPoint(x: $0.x + dx, y: $0.y + dy, confidence: $0.confidence) }
        return copy
    }
}

nonisolated enum PoseMath {
    static func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let v1 = (dx: a.x - b.x, dy: a.y - b.y)
        let v2 = (dx: c.x - b.x, dy: c.y - b.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let m1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let m2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        guard m1 > 1e-6, m2 > 1e-6 else { return 180 }
        let cosValue = max(-1, min(1, dot / (m1 * m2)))
        return acos(cosValue) * 180 / .pi
    }

    /// Torso lean from vertical, in degrees.
    static func torsoAngle(_ frame: PoseFrame) -> Double? {
        guard let neck = frame.pt(J.neck),
              let hip = frame.mid(J.leftHip, J.rightHip) ?? frame.pt(J.root) else { return nil }
        let dx = neck.x - hip.x
        let dy = neck.y - hip.y
        guard sqrt(dx * dx + dy * dy) > 1e-6 else { return nil }
        let vertical = acos(max(-1, min(1, dy / sqrt(dx * dx + dy * dy)))) * 180 / .pi
        return vertical
    }
}

/// A flagged moment on the playback timeline.
struct Moment: Codable, Sendable, Hashable {
    var time: Float
    var message: String
    /// The failed check's key, used to highlight the joints involved. Optional so
    /// reports saved before this field existed still decode.
    var fault: String?
}

/// Result of one repetition (or the single hold for a plank).
struct RepResult: Codable, Sendable, Identifiable {
    var id: Int
    var score: Int
    var start: Float
    var bottom: Float
    var end: Float
    var faults: [String]
}

struct FeedbackItem: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var title: String
}

struct WorkoutAnalysis: Codable, Sendable {
    var exercise: Exercise
    var duration: Float
    var videoAspect: Float
    var overallScore: Int
    var reps: [RepResult]
    var strengths: [FeedbackItem]
    var fixes: [FeedbackItem]
    var frames: [PoseFrame]
    var flags: [Moment]
    var tempoLabel: String
    /// Present only when the analysis measured camera movement. Optional so
    /// reports saved before this field existed still decode.
    var cameraMotion: CameraMotion?
}

/// How readily camera movement flags a report. Low only reacts to obvious
/// panning, High reacts to smaller wobbles. Stored as a raw string in settings.
nonisolated enum MotionSensitivity: String, CaseIterable, Codable {
    case low, medium, high

    /// Fraction of sampled frame pairs above which a clip counts as moving.
    var threshold: Float {
        switch self {
        case .low: 0.35
        case .medium: 0.2
        case .high: 0.1
        }
    }

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var explanation: String {
        switch self {
        case .low: "Only clearly panned footage gets flagged — fewer warnings, shakier clips judged as-is."
        case .medium: "Balanced. Flags clips where the camera really moved."
        case .high: "Strict. Even small wobbles get flagged and shaky checks get skipped."
        }
    }

    static let `default`: MotionSensitivity = .medium
}

/// How much the camera moved during a clip, measured by aligning consecutive
/// frames. The person moving can't shift the whole frame — only the camera can.
nonisolated struct CameraMotion: Codable, Sendable {
    /// Fraction of sampled frame pairs (0–1) whose whole image shifted noticeably.
    var unstableFraction: Float
    /// Largest single pair-to-pair shift seen, as a fraction of frame width.
    var maxPairShift: Float?
    /// Whether pose data was steadied by subtracting the camera's drift before
    /// scoring. Nil for reports saved before correction existed.
    var corrected: Bool?

    init(unstableFraction: Float, maxPairShift: Float? = nil, corrected: Bool? = nil) {
        self.unstableFraction = unstableFraction
        self.maxPairShift = maxPairShift
        self.corrected = corrected
    }

    func isUnstable(threshold: Float) -> Bool { unstableFraction >= threshold }

    /// Judged at the default sensitivity, for callers without settings handy.
    var isUnstable: Bool { isUnstable(threshold: MotionSensitivity.default.threshold) }
}

enum AnalysisError: LocalizedError {
    case videoUnavailable
    case noPersonDetected

    var errorDescription: String? {
        switch self {
        case .videoUnavailable:
            "That video couldn't be read. Try a different recording."
        case .noPersonDetected:
            "We couldn't find a person in the video. Make sure your whole body is in frame."
        }
    }
}
