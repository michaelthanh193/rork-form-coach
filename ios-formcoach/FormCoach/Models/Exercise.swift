//
//  Exercise.swift
//  FormCoach
//
//  Everything FormCoach can analyze: six strength basics plus the nine
//  HYROX race segments, listed in race order.
//

import Foundation

enum ExerciseCategory: String, CaseIterable, Identifiable {
    case strength
    case hyrox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: "Strength"
        case .hyrox: "HYROX"
        }
    }
}

/// How an exercise is broken down for scoring.
enum ExerciseMeasure {
    /// Discrete repetitions (squat, wall ball, burpee broad jump…).
    case reps
    /// Machine strokes (SkiErg, rowing).
    case strokes
    /// A single timed hold (plank).
    case hold
    /// Continuous effort scored in fixed time windows (run, sleds, carry).
    case segments
}

enum Exercise: String, Codable, CaseIterable, Identifiable {
    // Strength basics
    case squat
    case pushUp
    case lunge
    case plank
    case jumpingJack
    case bicepCurl

    // HYROX race segments, in race order
    case run
    case skiErg
    case sledPush
    case sledPull
    case burpeeBroadJump
    case row
    case farmersCarry
    case sandbagLunge
    case wallBall

    var id: String { rawValue }

    var category: ExerciseCategory {
        switch self {
        case .squat, .pushUp, .lunge, .plank, .jumpingJack, .bicepCurl: .strength
        default: .hyrox
        }
    }

    var displayName: String {
        switch self {
        case .squat: "Squat"
        case .pushUp: "Push-up"
        case .lunge: "Lunge"
        case .plank: "Plank"
        case .jumpingJack: "Jumping Jack"
        case .bicepCurl: "Bicep Curl"
        case .run: "Run"
        case .skiErg: "SkiErg"
        case .sledPush: "Sled Push"
        case .sledPull: "Sled Pull"
        case .burpeeBroadJump: "Burpee Broad Jump"
        case .row: "Rowing"
        case .farmersCarry: "Farmers Carry"
        case .sandbagLunge: "Sandbag Lunges"
        case .wallBall: "Wall Balls"
        }
    }

    var symbolName: String {
        switch self {
        case .squat: "figure.strengthtraining.traditional"
        case .pushUp: "figure.core.training"
        case .lunge: "figure.walk"
        case .plank: "figure.yoga"
        case .jumpingJack: "figure.jumprope"
        case .bicepCurl: "figure.strengthtraining.functional"
        case .run: "figure.run"
        case .skiErg: "figure.skiing.crosscountry"
        case .sledPush: "figure.cross.training"
        case .sledPull: "figure.mixed.cardio"
        case .burpeeBroadJump: "figure.highintensity.intervaltraining"
        case .row: "figure.rower"
        case .farmersCarry: "figure.walk.motion"
        case .sandbagLunge: "figure.step.training"
        case .wallBall: "figure.handball"
        }
    }

    var measure: ExerciseMeasure {
        switch self {
        case .plank: .hold
        case .skiErg, .row: .strokes
        case .run, .sledPush, .sledPull, .farmersCarry: .segments
        default: .reps
        }
    }

    /// A plank is a timed hold rather than counted repetitions.
    var isHold: Bool { measure == .hold }

    /// Singular name for one scored unit ("rep", "stroke", "segment", "hold").
    var unitSingular: String {
        switch measure {
        case .reps: "rep"
        case .strokes: "stroke"
        case .hold: "hold"
        case .segments: "segment"
        }
    }

    /// "12 reps", "1 stroke", "9 segments", or "Hold".
    func countLabel(_ count: Int) -> String {
        if isHold { return "Hold" }
        return "\(count) \(unitSingular)\(count == 1 ? "" : "s")"
    }

    /// Camera advice shown before analysis starts.
    var filmingHint: String {
        switch self {
        case .run: "Film from the side on a treadmill or a fixed spot — about 5 m away."
        case .skiErg: "Film from the side so your hands, hips and knees stay in frame."
        case .sledPush, .sledPull: "Film from the side and keep the camera still — don't follow the sled."
        case .burpeeBroadJump: "Use a fixed camera from the side so jump distance can be measured."
        case .row: "Film from the side, level with the seat."
        case .farmersCarry: "Film from the front or side as you walk past."
        case .sandbagLunge: "Film from the side as you lunge across the frame."
        case .wallBall: "Film from the side with your whole body and the throw in frame."
        default: "Film from the side for the best read of your form."
        }
    }
}
