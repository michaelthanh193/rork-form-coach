//
//  HistoryView.swift
//  FormCoach
//
//  Every analyzed session, newest first. Tap to reopen the report, swipe to delete.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @Environment(\.modelContext) private var modelContext

    @State private var isSelecting = false
    @State private var selection: [WorkoutSession] = []
    @State private var pendingDeletion: PendingDeletion?
    @State private var countdownStarted = false

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.ink)
        .navigationTitle(isSelecting ? "Select two" : "History")
        .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSelecting.toggle()
                        if !isSelecting { selection = [] }
                    }
                } label: {
                    if isSelecting {
                        Text("Done")
                            .fontWeight(.semibold)
                    } else {
                        Label("Compare sessions", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { compareBar }
        }
        .overlay(alignment: .bottom) { undoToast }
        .task(id: pendingDeletion?.id) {
            guard pendingDeletion != nil else { return }
            countdownStarted = false
            withAnimation(.linear(duration: 5)) { countdownStarted = true }
            try? await Task.sleep(for: .seconds(5))
            finalizeDeletion()
        }
    }

    /// The two picked sessions, or nil until exactly two same-exercise sessions are selected.
    private var comparePair: (WorkoutSession, WorkoutSession)? {
        guard selection.count == 2, selection[0].exercise == selection[1].exercise else { return nil }
        return (selection[0], selection[1])
    }

    private var compareBar: some View {
        VStack(spacing: 0) {
            if let pair = comparePair {
                NavigationLink(value: AppRoute.compare(pair.0, pair.1)) {
                    Label("Compare \(selection[0].exercise.displayName.lowercased()) sessions", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.inkOnLime)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                                .fill(Theme.lime)
                        )
                }
                .buttonStyle(PressableButtonStyle())
            } else {
                Text(hintText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var hintText: String {
        if selection.count == 2 {
            return "Those are different exercises — pick two of the same."
        }
        return "Pick two sessions of the same exercise to compare"
    }

    private func toggleSelection(_ session: WorkoutSession) {
        if let index = selection.firstIndex(where: { $0.id == session.id }) {
            selection.remove(at: index)
        } else {
            if selection.count == 2 { selection.removeFirst() }
            selection.append(session)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessions) { session in
                    Group {
                        if isSelecting {
                            Button {
                                toggleSelection(session)
                            } label: {
                                HistoryRow(session: session)
                                    .overlay(alignment: .topTrailing) { selectionBadge(session) }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                                            .strokeBorder(isSelected(session) ? Theme.lime : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(PressableButtonStyle())
                        } else {
                            SwipeToDelete {
                                delete(session)
                            } content: {
                                NavigationLink(value: AppRoute.report(session)) {
                                    HistoryRow(session: session)
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    delete(session)
                                } label: {
                                    Label("Delete session", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.margin)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .report(let session):
                FormReportView(session: session)
            case .compare(let a, let b):
                ComparisonView(a, b)
            }
        }
    }

    private func isSelected(_ session: WorkoutSession) -> Bool {
        selection.contains(where: { $0.id == session.id })
    }

    private func selectionBadge(_ session: WorkoutSession) -> some View {
        Group {
            if isSelected(session) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.lime, Theme.ink)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(10)
    }

    private func delete(_ session: WorkoutSession) {
        // Flush any earlier pending deletion so its video file isn't orphaned.
        finalizeDeletion()

        let snapshot = PendingDeletion(
            id: session.id,
            date: session.date,
            exercise: session.exercise,
            overallScore: session.overallScore,
            repCount: session.repCount,
            duration: session.duration,
            videoFileName: session.videoFileName,
            analysisData: session.analysisData
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            modelContext.delete(session)
            try? modelContext.save()
            pendingDeletion = snapshot
        }
    }

    private func undoDeletion() {
        guard let pending = pendingDeletion else { return }
        // Rebuild the session with its original data; the video file was kept.
        let restored = WorkoutSession(
            exercise: pending.exercise,
            overallScore: pending.overallScore,
            repCount: pending.repCount,
            duration: pending.duration,
            videoFileName: pending.videoFileName,
            analysis: WorkoutAnalysis(
                exercise: pending.exercise,
                duration: pending.duration,
                videoAspect: 1,
                overallScore: pending.overallScore,
                reps: [], strengths: [], fixes: [], frames: [], flags: [], tempoLabel: ""
            )
        )
        restored.analysisData = pending.analysisData
        restored.date = pending.date
        modelContext.insert(restored)
        try? modelContext.save()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            pendingDeletion = nil
        }
    }

    /// Called when the undo window closes: the video file is removed for good.
    private func finalizeDeletion() {
        guard let pending = pendingDeletion else { return }
        if !pending.videoFileName.isEmpty {
            try? FileManager.default.removeItem(at: WorkoutSession.makeVideoURL(fileName: pending.videoFileName))
        }
        withAnimation { pendingDeletion = nil }
    }

    // MARK: - Undo toast

    private var undoToast: some View {
        Group {
            if let pending = pendingDeletion {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.coral)
                        Text("\(pending.exercise.displayName) session deleted")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Button {
                            undoDeletion()
                        } label: {
                            Text("Undo")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.lime)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.stroke)
                            Rectangle()
                                .fill(Theme.lime)
                                .frame(width: countdownStarted ? 0 : geo.size.width)
                        }
                    }
                    .frame(height: 3)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surfaceElevated)
                )
                .clipShape(.rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.stroke)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 38))
                .foregroundStyle(Theme.textSecondary)
            Text("No sessions yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Every workout you analyze lands here so you can track how your form improves.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Snapshot of a session awaiting deletion; kept so the undo window can restore it.
private struct PendingDeletion: Identifiable {
    let id: UUID
    let date: Date
    let exercise: Exercise
    let overallScore: Int
    let repCount: Int
    let duration: Float
    let videoFileName: String
    let analysisData: Data
}

private struct HistoryRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 14) {
            VideoThumb(url: session.videoURL)
                .frame(width: 84, height: 62)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.exercise.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if session.exercise.category == .hyrox {
                        HyroxTag()
                    }
                }
                Text("\(session.exercise.countLabel(session.repCount)) · \(session.date.historyLabel)")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.overallScore)")
                    .font(.mono(24, weight: .heavy))
                    .foregroundStyle(session.overallScore < 60 ? Theme.coral : Theme.lime)
                Text("score")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .cardBackground()
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
