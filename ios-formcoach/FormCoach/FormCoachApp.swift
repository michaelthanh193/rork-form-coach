//
//  FormCoachApp.swift
//  FormCoach
//
//  Created by Rork on October 17, 2026.
//

import SwiftUI
import SwiftData

@main
struct FormCoachApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: WorkoutSession.self)
        }
    }
}
