//
//  ComparisonView.swift
//  FormCoach
//
//  Side-by-side comparison of two sessions of the same exercise:
//  score rings, the delta between them, and aligned per-rep bars.
//

import SwiftUI

struct ComparisonView: View {
    let earlier: WorkoutSession
    let later: WorkoutSession

    /// Accepts the two sessions in any order and keeps them chronological.
    init(_ a: WorkoutSession, _ b: WorkoutSession) {
        if a.date <= b.date {
            earlier = a
            later = b
        } else {
            earlier = b
            later = a
        }
    }

    private var delta: Int { later.overallScore - earlier.overallScore }
    private var isHold: Bool { earlier.exercise.isHold }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    deltaCard
                    scoresCard
                    repBarsCard
                }
                .padding(Theme.margin)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(earlier.exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
    }

    // MARK: - Delta headline

    private var deltaCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: deltaImageName)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(deltaColor)
                Text("\(abs(delta))")
                    .font(.mono(48, weight: .heavy))
                    .foregroundStyle(deltaColor)
                    .contentTransition(.numericText())
                Text("points")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(deltaHeadline)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(16)
        .cardBackground()
    }

    private var deltaImageName: String {
        if delta > 0 { return "arrow.up.right" }
        if delta < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var deltaColor: Color {
        if delta > 0 { return Theme.lime }
        if delta < 0 { return Theme.coral }
        return Theme.textSecondary
    }

    private var deltaHeadline: String {
        let latest = later.date.historyLabel
        switch delta {
        case let d where d > 0:
            return "Your \(earlier.exercise.displayName.lowercased()) form improved \(delta) points since \(latest.lowercased())"
        case let d where d < 0:
            return "Down \(abs(delta)) points from \(latest.lowercased()) — check what changed below"
        default:
            return "Holding steady at \(earlier.overallScore) points"
        }
    }

    // MARK: - Score columns

    private var scoresCard: some View {
        HStack(alignment: .top, spacing: 0) {
            column(for: earlier, label: "Earlier")
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1, height: 150)
            column(for: later, label: "Latest")
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .cardBackground()
    }

    private func column(for session: WorkoutSession, label: String) -> some View {
        VStack(spacing: 10) {
            Text(label.uppercased())
                .sectionLabel()
            ScoreRing(score: session.overallScore, size: 84, lineWidth: 8)
            VStack(spacing: 2) {
                Text(session.date.historyLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(metadataLine(session))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
    }

    private func metadataLine(_ session: WorkoutSession) -> String {
        if isHold {
            return "\(Int(session.duration.rounded())) sec hold"
        }
        return "\(session.exercise.countLabel(session.repCount)) · \(Int(session.duration.rounded())) sec"
    }

    // MARK: - Per-rep bars

    private var repBarsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isHold ? "Hold" : "\(earlier.exercise.unitSingular.capitalized) scores")
                .sectionLabel()
            CompareRepRow(title: earlier.date.historyLabel, reps: earlier.analysis?.reps ?? [], isHold: isHold)
            Divider().overlay(Theme.stroke)
            CompareRepRow(title: later.date.historyLabel, reps: later.analysis?.reps ?? [], isHold: isHold)
        }
        .padding(16)
        .cardBackground()
    }
}

/// One session's per-rep bars, animated on appear. Both rows share the 0–100 scale.
private struct CompareRepRow: View {
    let title: String
    let reps: [RepResult]
    let isHold: Bool

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                if !reps.isEmpty {
                    Text(averageLabel)
                        .font(.mono(13, weight: .bold))
                        .foregroundStyle(average < 60 ? Theme.coral : Theme.lime)
                }
            }
            if reps.isEmpty {
                Text("No score data for this session.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScoreBarChart(reps: reps, barAreaHeight: 70, maxBarWidth: 16, appeared: appeared) { rep in
                    isHold ? "•" : "\(rep.score)"
                }
                .frame(height: 92)
            }
        }
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) {
                appeared = true
            }
        }
    }

    private var average: Int {
        guard !reps.isEmpty else { return 0 }
        return Int((reps.map(\.score).reduce(0, +) + reps.count / 2) / reps.count)
    }

    private var averageLabel: String {
        isHold ? "\(average) avg" : "avg \(average)"
    }

}

private extension Date {
    var historyLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}
