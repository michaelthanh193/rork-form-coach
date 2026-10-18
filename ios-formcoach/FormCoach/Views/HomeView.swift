//
//  HomeView.swift
//  FormCoach
//
//  Coach dashboard: headline form score, quick analyze, week strip, recent session.
//

import SwiftUI
import PhotosUI
import SwiftData

struct HomeView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @Environment(SessionCoordinator.self) private var coordinator

    @State private var pickerItem: PhotosPickerItem?
    @State private var isPreparingVideo = false
    @State private var showSourceDialog = false
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                scoreCard
                statTiles
                analyzeButton
                WeekStrip(dayTotals: weekReps)
                recentCard
            }
            .padding(Theme.margin)
            .padding(.bottom, 24)
        }
        .background(Theme.ink)
        .scrollBounceBehavior(.basedOnSize)
        .photosPicker(isPresented: $isPreparingVideo, selection: $pickerItem, matching: .videos)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                onFinish: { url in
                    showCamera = false
                    coordinator.pendingVideo = url
                },
                onClose: { showCamera = false },
                onPickFromLibrary: { isPreparingVideo = true }
            )
        }
        .confirmationDialog(
            "Analyze a workout",
            isPresented: $showSourceDialog,
            titleVisibility: .visible
        ) {
            Button("Film now") { showCamera = true }
            Button("Choose from library") { isPreparingVideo = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Film a new clip, or pick one you already recorded.")
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadVideo(from: newItem) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FormCoach")
                    .font(.display(34))
                    .foregroundStyle(Theme.textPrimary)
                + Text("Coach")
                    .font(.display(34))
                    .foregroundStyle(Theme.lime)
                Text("Better form. A stronger you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surfaceElevated))
        }
        .padding(.top, 8)
    }

    // MARK: - Score card

    private var scoreCard: some View {
        HStack(spacing: 20) {
            ScoreRing(score: averageScore, size: 110, lineWidth: 11)
            VStack(alignment: .leading, spacing: 8) {
                Text("Average form score")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if let trend = weeklyTrend, trend != 0 {
                    Label {
                        Text("\(trend > 0 ? "+" : "")\(trend) from last week")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    } icon: {
                        Image(systemName: trend > 0 ? "arrow.trend.up" : "arrow.trend.down")
                            .foregroundStyle(trend > 0 ? Theme.lime : Theme.coral)
                    }
                } else {
                    Text(tempoCaption)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                weekSparkline
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .cardBackground()
    }

    private var tempoCaption: String {
        sessions.isEmpty ? "Analyze your first workout" : "Keep the streak going"
    }

    /// Daily average scores this week, Monday-first.
    private var weekSparkline: some View {
        let scores = averageScorePerDay
        return VStack(alignment: .leading, spacing: 4) {
            Sparkline(values: scores)
                .frame(height: 36)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(HomeMath.dayLetters[index])
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: 150)
    }

    // MARK: - Stat tiles

    private var statTiles: some View {
        HStack(spacing: 12) {
            StatTile(icon: "chart.bar.fill", value: "\(sessions.count)", caption: "Sessions analyzed")
            StatTile(icon: "dumbbell.fill", value: "\(totalReps)", caption: "Reps counted")
        }
    }

    // MARK: - Analyze button

    private var analyzeButton: some View {
        Button {
            showSourceDialog = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 20, weight: .bold))
                Text("Analyze a workout")
                    .font(.system(size: 19, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Theme.inkOnLime)
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(Theme.lime)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Recent

    private var recentCard: some View {
        Group {
            if let recent = sessions.first {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent")
                        .sectionLabel()
                    Button {
                        coordinator.openReport(recent)
                    } label: {
                        HStack(spacing: 14) {
                            VideoThumb(url: recent.videoURL)
                                .frame(width: 86, height: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recent.exercise.displayName)
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(recent.exercise.isHold ? "Held" : recent.exercise.countLabel(recent.repCount)) · \(recent.date.relativeDaysAgo)")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Text("\(recent.overallScore)")
                                .font(.mono(28, weight: .heavy))
                                .foregroundStyle(Theme.lime)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.surfaceElevated)
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.textSecondary)
                    Text("No sessions yet")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Analyze your first workout video and your coach dashboard will fill up here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 20)
                .cardBackground()
            }
        }
    }

    // MARK: - Derived stats

    private var averageScore: Int {
        guard !sessions.isEmpty else { return 0 }
        let total = sessions.reduce(0) { $0 + $1.overallScore }
        return Int((Double(total) / Double(sessions.count)).rounded())
    }

    /// Reps and strokes only — time-based segments (run, sleds, carry) aren't reps.
    private var totalReps: Int {
        sessions
            .filter { $0.exercise.measure == .reps || $0.exercise.measure == .strokes }
            .reduce(0) { $0 + $1.repCount }
    }

    private var calendar: Calendar { Calendar.current }

    /// Reps completed on each day of the current week (Mon-first).
    private var weekReps: [Double?] {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var totals = [Double?](repeating: nil, count: 7)
        for session in sessions {
            let offset = calendar.dateComponents([.day], from: startOfWeek, to: session.date).day ?? -1
            guard (0..<7).contains(offset) else { continue }
            totals[offset] = (totals[offset] ?? 0) + Double(session.repCount)
        }
        // A hold session still counts as activity on its day.
        for (index, value) in totals.enumerated() where value == nil {
            let dayHasHold = sessions.contains {
                let offset = calendar.dateComponents([.day], from: startOfWeek, to: $0.date).day ?? -1
                return offset == index && $0.exercise.isHold
            }
            if dayHasHold { totals[index] = 1 }
        }
        return totals
    }

    /// Average form score per day this week for the sparkline.
    private var averageScorePerDay: [Double?] {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var buckets: [[Int]] = Array(repeating: [], count: 7)
        for session in sessions {
            let offset = calendar.dateComponents([.day], from: startOfWeek, to: session.date).day ?? -1
            guard (0..<7).contains(offset) else { continue }
            buckets[offset].append(session.overallScore)
        }
        return buckets.map { bucket in
            bucket.isEmpty ? nil : Double(bucket.reduce(0, +) / bucket.count)
        }
    }

    private var weeklyTrend: Int? {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek)
        let lastWeekEnd = calendar.date(byAdding: .day, value: 6, to: lastWeekStart ?? startOfWeek)

        func average(_ range: (Date) -> Bool) -> Double? {
            let inRange = sessions.filter { range($0.date) }
            guard !inRange.isEmpty else { return nil }
            return Double(inRange.reduce(0) { $0 + $1.overallScore }) / Double(inRange.count)
        }

        guard let last = average({ $0 >= lastWeekStart! && $0 <= lastWeekEnd! }),
              let current = average({ $0 >= startOfWeek }) else { return nil }
        return Int(current - last)
    }

    // MARK: - Video loading

    private func loadVideo(from item: PhotosPickerItem) async {
        isPreparingVideo = false
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try data.write(to: tempURL)
            coordinator.pendingVideo = tempURL
        } catch {
            // The picker item couldn't be read; quietly ignore and let the user retry.
        }
        pickerItem = nil
    }
}

private enum HomeMath {
    static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double?]

    var body: some View {
        Canvas { context, size in
            let points = values.enumerated().compactMap { index, value -> CGPoint? in
                guard let value else { return nil }
                let x = size.width * (Double(index) + 0.5) / 7
                let y = size.height * (1 - CGFloat(value) / 100)
                return CGPoint(x: x, y: y)
            }
            guard points.count >= 2 else {
                if let only = points.first {
                    context.fill(Path(ellipseIn: CGRect(x: only.x - 3, y: only.y - 3, width: 6, height: 6)), with: .color(Theme.lime))
                }
                return
            }
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            context.stroke(path, with: .color(Theme.lime), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            for point in points {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(Theme.lime))
            }
        }
    }
}

// MARK: - Helpers

extension Date {
    func relativeDaysAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

/// Subtle scale-down press feedback for the app's chunky buttons.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
