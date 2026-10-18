//
//  WorkoutSession.swift
//  FormCoach
//
//  A saved analysis, persisted with SwiftData. The source video is copied into
//  the app's documents folder so past reports can be replayed with the skeleton.
//

import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var exerciseRaw: String = Exercise.squat.rawValue
    var overallScore: Int = 0
    var repCount: Int = 0
    var duration: Float = 0
    var videoFileName: String = ""
    var analysisData: Data = Data()

    init(exercise: Exercise, overallScore: Int, repCount: Int, duration: Float, videoFileName: String, analysis: WorkoutAnalysis) {
        self.id = UUID()
        self.date = Date()
        self.exerciseRaw = exercise.rawValue
        self.overallScore = overallScore
        self.repCount = repCount
        self.duration = duration
        self.videoFileName = videoFileName
        self.analysisData = (try? JSONEncoder().encode(analysis)) ?? Data()
    }

    var exercise: Exercise { Exercise(rawValue: exerciseRaw) ?? .squat }

    var analysis: WorkoutAnalysis? {
        get { analysisData.isEmpty ? nil : try? JSONDecoder().decode(WorkoutAnalysis.self, from: analysisData) }
        set { analysisData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    static func videosDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("videos", isDirectory: true)
    }

    static func makeVideoURL(fileName: String) -> URL {
        videosDirectory().appendingPathComponent(fileName)
    }

    var videoURL: URL? {
        guard !videoFileName.isEmpty else { return nil }
        let url = Self.makeVideoURL(fileName: videoFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
