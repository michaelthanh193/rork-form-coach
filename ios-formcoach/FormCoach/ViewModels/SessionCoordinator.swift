//
//  SessionCoordinator.swift
//  FormCoach
//
//  Shared navigation state: the analyze flow, the Home tab's navigation
//  path, and which tab is active.
//

import SwiftUI

enum AppRoute: Hashable {
    case report(WorkoutSession)
    /// Side-by-side comparison of two same-exercise sessions.
    case compare(WorkoutSession, WorkoutSession)
}

@Observable
@MainActor
final class SessionCoordinator {
    var homePath: [AppRoute] = []
    /// Videos selected for analysis, presented as a full-screen analyze flow.
    var pendingVideo: URL?
    /// Exercise chosen before filming, preselected in the analyze flow.
    var pendingExercise: Exercise?
    var selectedTab: Int = 0

    func openReport(_ session: WorkoutSession) {
        selectedTab = 0
        homePath.append(.report(session))
    }

    func closeAnalyzeFlow() {
        pendingVideo = nil
        pendingExercise = nil
    }
}
