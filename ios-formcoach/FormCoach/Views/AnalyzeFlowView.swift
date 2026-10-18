//
//  AnalyzeFlowView.swift
//  FormCoach
//
//  Full-screen analyze flow: video preview, exercise chips, animated
//  "studying your movement" progress, then hands off to the form report.
//

import SwiftUI
import AVFoundation
import SwiftData

struct AnalyzeFlowView: View {
    let videoURL: URL
    /// Exercise chosen before filming (Library shortcut) — preselected, never asked again.
    var presetExercise: Exercise?

    @Environment(SessionCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    private enum Phase: Equatable {
        case setup
        case analyzing
        case failed(String)
    }

    @State private var phase: Phase = .setup
    @State private var exercise: Exercise?
    @State private var wasPreset = false
    @State private var category: ExerciseCategory = .strength
    @Namespace private var categoryNamespace
    @State private var progress = PoseAnalyzer.Progress()
    @State private var analysis: WorkoutAnalysis?
    @State private var analysisTask: Task<Void, Never>?
    @State private var savedVideoURL: URL?

    var body: some View {
        ZStack(alignment: .top) {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 0) {
                videoHeader
                VStack(alignment: .leading, spacing: 18) {
                    exerciseChips
                    switch phase {
                    case .setup: setupContent
                    case .analyzing: analyzingContent
                    case .failed(let message): failedContent(message)
                    }
                }
                .padding(Theme.margin)
                Spacer(minLength: 0)
            }
        }
        .statusBarHidden()
        .task(id: videoURL) {
            if let presetExercise, !wasPreset {
                exercise = presetExercise
                category = presetExercise.category
                wasPreset = true
            }
            await prepareSavedCopy()
        }
        .onDisappear {
            analysisTask?.cancel()
        }
    }

    // MARK: - Video header

    private var videoHeader: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VideoThumb(url: savedVideoURL ?? videoURL, cornerRadius: 0)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay(alignment: .center) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 12)
                    }
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, Theme.ink.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                            .allowsHitTesting(false)
                    }
                Button {
                    analysisTask?.cancel()
                    coordinator.closeAnalyzeFlow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
                .padding(12)
            }
        }
        .frame(height: 260)
    }

    // MARK: - Exercise chips

    private var exerciseChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category == .hyrox ? "Choose a station" : "Choose an exercise")
                    .sectionLabel()
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
                categorySwitch
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Exercise.allCases.filter { $0.category == category }) { candidate in
                        ExerciseChip(
                            exercise: candidate,
                            isSelected: exercise == candidate
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                exercise = candidate
                            }
                        }
                    }
                }
            }
            .id(category)
            .transition(.opacity)
            .disabled(phase == .analyzing)
        }
    }

    private var categorySwitch: some View {
        HStack(spacing: 2) {
            ForEach(ExerciseCategory.allCases) { option in
                Button {
                    guard category != option else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        category = option
                        if exercise?.category != option { exercise = nil }
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .bold))
                        .kerning(option == .hyrox ? 0.8 : 0)
                        .foregroundStyle(category == option ? Theme.inkOnLime : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background {
                            if category == option {
                                Capsule()
                                    .fill(Theme.lime)
                                    .matchedGeometryEffect(id: "categoryPill", in: categoryNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        .disabled(phase == .analyzing)
    }

    // MARK: - Phases

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .foregroundStyle(Theme.textSecondary)
                Text(exercise?.filmingHint ?? (category == .hyrox
                    ? "Pick a station — each one is judged on its own race standards."
                    : "Film from the side for the best read of your form."))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Button {
                startAnalysis()
            } label: {
                Text("Start analysis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(exercise == nil ? Theme.textSecondary : Theme.inkOnLime)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                            .fill(exercise == nil ? Theme.surfaceElevated : Theme.lime)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(exercise == nil)
        }
        .padding(.top, 8)
    }

    private var analyzingContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Studying your movement…")
                    .font(.display(22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 12) {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(Theme.lime)
                        .scaleEffect(y: 2.2, anchor: .center)
                        .padding(.vertical, 6)
                    Text("\(Int((progress.fraction * 100).rounded()))%")
                        .font(.mono(18, weight: .bold))
                        .foregroundStyle(Theme.lime)
                        .monospacedDigit()
                }
            }
            .padding(.top, 10)

            HStack(spacing: 0) {
                progressCounter(icon: "video.fill", value: "\(progress.framesProcessed)", caption: "frames")
                progressCounter(icon: "chart.bar.fill", value: "\(progress.repsFound)", caption: progressCaption)
            }
            .padding(16)
            .cardBackground()

            Text("Your video never leaves this device.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var progressCaption: String {
        guard let exercise else { return "reps found" }
        if exercise.isHold { return "hold" }
        return "\(exercise.unitSingular)s found"
    }

    private func progressCounter(icon: String, value: String, caption: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.surfaceElevated))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.mono(24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 16)
    }

    private func failedContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.coral)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()

            Button {
                phase = .setup
            } label: {
                Text("Try again")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.inkOnLime)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                            .fill(Theme.lime)
                    )
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func prepareSavedCopy() async {
        let destination = WorkoutSession.makeVideoURL(fileName: UUID().uuidString + ".mov")
        do {
            try FileManager.default.createDirectory(at: WorkoutSession.videosDirectory(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: videoURL, to: destination)
            savedVideoURL = destination
        } catch {
            savedVideoURL = videoURL
        }
    }

    private func startAnalysis() {
        guard let exercise else { return }
        phase = .analyzing
        progress = PoseAnalyzer.Progress()

        let workingURL = savedVideoURL ?? videoURL
        analysisTask = Task {
            do {
                let analyzer = PoseAnalyzer()
                let result = try await analyzer.analyze(videoURL: workingURL, exercise: exercise) { updated in
                    Task { @MainActor in
                        guard !Task.isCancelled else { return }
                        progress = updated
                    }
                }
                guard !Task.isCancelled else { return }
                finish(with: result, exercise: exercise, videoURL: workingURL)
            } catch is CancellationError {
                // User backed out; nothing to do.
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func finish(with analysis: WorkoutAnalysis, exercise: Exercise, videoURL: URL) {
        let fileName = videoURL.lastPathComponent
        let session = WorkoutSession(
            exercise: exercise,
            overallScore: analysis.overallScore,
            repCount: analysis.reps.count,
            duration: analysis.duration,
            videoFileName: fileName,
            analysis: analysis
        )
        modelContext.insert(session)
        try? modelContext.save()
        self.analysis = analysis
        coordinator.closeAnalyzeFlow()
        coordinator.openReport(session)
    }
}

private struct ExerciseChip: View {
    let exercise: Exercise
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: exercise.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                Text(exercise.displayName)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.inkOnLime : Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(
                Capsule().fill(isSelected ? Theme.lime : Theme.surface)
            )
            .overlay(Capsule().strokeBorder(isSelected ? Theme.lime : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
