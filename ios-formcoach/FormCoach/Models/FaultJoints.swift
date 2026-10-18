//
//  FaultJoints.swift
//  FormCoach
//
//  Which skeleton joints each form check is about, so a flagged moment can
//  light up exactly the part of the body that went wrong.
//

import Foundation

nonisolated enum FaultJoints {

    private static let knees: Set<Int> = [J.leftKnee, J.rightKnee]
    private static let hips: Set<Int> = [J.leftHip, J.rightHip, J.root]
    private static let ankles: Set<Int> = [J.leftAnkle, J.rightAnkle]
    private static let elbows: Set<Int> = [J.leftElbow, J.rightElbow]
    private static let wrists: Set<Int> = [J.leftWrist, J.rightWrist]
    private static let shoulders: Set<Int> = [J.leftShoulder, J.rightShoulder]
    private static let spine: Set<Int> = [J.neck, J.root]

    /// Joint indices to highlight for a fault on a given exercise.
    static func joints(for fault: String, exercise: Exercise) -> Set<Int> {
        // Depth on a push-up is about the arms, not the legs.
        if fault == "shallow_depth", exercise == .pushUp { return elbows.union(shoulders) }

        switch fault {
        case "shallow_depth", "slow_tempo", "fast_tempo", "slow_getup", "standing_tall":
            return hips.union(knees)
        case "knee_drift", "knee_no_touch", "squatting", "short_drive":
            return knees
        case "torso_lean", "body_swing", "too_upright", "run_lean", "over_layback":
            return spine.union(hips)
        case "hip_sag", "hip_pike", "heavy_bounce":
            return hips
        case "no_hinge":
            return spine.union(hips)
        case "knee_over_toe", "overstriding", "short_catch":
            return knees.union(ankles)
        case "short_jump", "low_cadence":
            return ankles.union(hips)
        case "incomplete_extension", "incomplete_contraction", "no_extension_throw", "incomplete_raise":
            return elbows.union(wrists)
        case "elbow_drift":
            return elbows.union(shoulders)
        case "arm_asymmetry", "short_pull", "short_reach":
            return wrists
        case "neck_crank":
            return [J.nose, J.neck]
        case "chest_not_down", "pull_hunch":
            return shoulders.union([J.neck])
        case "shoulder_tilt":
            return shoulders
        case "bent_arms", "arms_collapsed", "early_arms":
            return elbows
        case "arms_only":
            return elbows.union(hips)
        case "overreach":
            return shoulders.union(wrists)
        case "short_hold":
            return hips
        default:
            return []
        }
    }
}
