//
//  ContentView.swift
//  FormCoach
//
//  Root: four tabs (Home, Library, History, Settings), the analyze flow as a
//  full-screen cover, and the report pushed on the Home tab's navigation stack.
//

import SwiftUI

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ContentView: View {
    @State private var coordinator = SessionCoordinator()

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            NavigationStack(path: $coordinator.homePath) {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .report(let session):
                            FormReportView(session: session)
                        case .compare(let a, let b):
                            ComparisonView(a, b)
                        }
                    }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "play.rectangle.on.rectangle.fill") }
            .tag(1)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "list.clipboard.fill") }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(3)
        }
        .environment(coordinator)
        .fullScreenCover(item: Binding(
            get: { coordinator.pendingVideo },
            set: { coordinator.pendingVideo = $0 }
        )) { url in
            AnalyzeFlowView(videoURL: url, presetExercise: coordinator.pendingExercise)
        }
        .tint(Theme.lime)
        .preferredColorScheme(.dark)
    }
}
