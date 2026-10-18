//
//  LibraryView.swift
//  FormCoach
//
//  The Library tab: every Strength and HYROX movement with a live looping
//  skeleton demo, a Strength/HYROX switch, search, and a detail page with
//  the movement standard, playable faults and a shortcut to film it.
//

import SwiftUI
import Combine

// MARK: - Demo stage

/// Renders a looping demo skeleton on the ink canvas. Reuses `PoseOverlay`
/// so demos and workout replays share exactly the same skeleton styling.
struct DemoStage: View {
    let exercise: Exercise
    var fault: String? = nil
    var view: DemoView = .side
    var isPlaying: Bool = true
    var speed: Double = 1
    var sampleCount: Int = 48

    /// Position in the loop, seconds at 1×. Drives the drawn frame.
    @State private var playhead: Double = 0
    private let tick = Timer.publish(every: 1 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        PoseOverlay(
            frames: frames,
            videoAspect: 1,
            currentTime: playhead,
            highlightedJoints: highlight
        )
        .onReceive(tick) { _ in
            guard isPlaying else { return }
            playhead = (playhead + (1 / 30) * speed)
                .truncatingRemainder(dividingBy: loopLength)
        }
        .onChange(of: fault) { _, _ in playhead = 0 }
        .onChange(of: view) { _, _ in playhead = 0 }
    }

    private var highlight: Set<Int> {
        guard let fault else { return [] }
        return FaultJoints.joints(for: fault, exercise: exercise)
    }

    private var loopLength: Double {
        ExerciseDemos.duration(for: exercise) / ExerciseDemos.speed(fault: fault)
    }

    /// Pre-sampled loop; the fault angle picks the variant.
    private var frames: [PoseFrame] {
        ExerciseDemos.frames(for: exercise, fault: fault, view: view, count: sampleCount)
    }
}

// MARK: - Library tab

struct LibraryView: View {
    @Environment(SessionCoordinator.self) private var coordinator

    @State private var category: ExerciseCategory = .strength
    @State private var searchText = ""
    @State private var analyzeTarget: Exercise?
    @State private var showCamera = false

    private var exercises: [Exercise] {
        if !searchText.isEmpty {
            return Exercise.allCases.filter { $0.displayName.localizedStandardContains(searchText) }
        }
        return Exercise.allCases.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if searchText.isEmpty {
                        categorySwitch
                    }
                    exerciseGrid
                }
                .padding(Theme.margin)
                .padding(.bottom, 24)
            }
            .background(Theme.ink)
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Library")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search movements")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise) {
                    analyzeTarget = exercise
                    showCamera = true
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            if let target = analyzeTarget {
                CameraCaptureView(
                    onFinish: { url in
                        showCamera = false
                        coordinator.pendingExercise = target
                        coordinator.pendingVideo = url
                    },
                    onClose: { showCamera = false }
                )
            }
        }
    }

    // MARK: Grid

    private var categorySwitch: some View {
        HStack(spacing: 2) {
            ForEach(ExerciseCategory.allCases) { option in
                Button {
                    guard category != option else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        category = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .bold))
                        .kerning(option == .hyrox ? 0.8 : 0)
                        .foregroundStyle(category == option ? Theme.inkOnLime : Theme.textSecondary)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background {
                            if category == option {
                                Capsule().fill(Theme.lime)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == option ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var exerciseGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(exercises) { exercise in
                NavigationLink(value: exercise) {
                    LibraryCard(exercise: exercise, raceNumber: raceNumber(exercise))
                }
                .buttonStyle(PressableButtonStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                })
            }
        }
    }

    /// 1–9 in race order for HYROX stations, nil for strength basics.
    private func raceNumber(_ exercise: Exercise) -> Int? {
        guard exercise.category == .hyrox else { return nil }
        let hyrox = Exercise.allCases.filter { $0.category == .hyrox }
        return hyrox.firstIndex(of: exercise).map { $0 + 1 }
    }
}

// MARK: - Card

private struct LibraryCard: View {
    let exercise: Exercise
    let raceNumber: Int?

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DemoStage(exercise: exercise, view: ExerciseDemos.views(for: exercise)[0], isPlaying: isVisible, sampleCount: 32)
                .frame(height: 118)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    if let raceNumber {
                        Text("\(raceNumber)")
                            .font(.mono(12, weight: .heavy))
                            .foregroundStyle(Theme.inkOnLime)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.lime))
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottom) {
                    // Floor line grounds the figure.
                    Rectangle()
                        .fill(Theme.stroke)
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(measureLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.displayName), \(measureLabel)")
    }

    private var measureLabel: String {
        switch exercise.measure {
        case .reps: "Scored per rep"
        case .strokes: "Scored per stroke"
        case .hold: "Timed hold"
        case .segments: "Scored in segments"
        }
    }
}

// MARK: - Exercise detail

struct ExerciseDetailView: View {
    let exercise: Exercise
    let onAnalyze: () -> Void

    @State private var isPlaying = true
    @State private var speed: Double = 1
    @State private var demoView: DemoView
    @State private var selectedFault: String?

    init(exercise: Exercise, onAnalyze: @escaping () -> Void) {
        self.exercise = exercise
        self.onAnalyze = onAnalyze
        _demoView = State(initialValue: ExerciseDemos.views(for: exercise)[0])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                stage
                titleRow
                standardCard
                faultsCard
                analyzeButton
            }
            .padding(Theme.margin)
            .padding(.bottom, 24)
        }
        .background(Theme.ink)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .onChange(of: selectedFault) { _, _ in
            // A fault may demand a different camera angle.
            demoView = ExerciseDemos.view(for: exercise, fault: selectedFault)
        }
    }

    // MARK: Stage

    private var stage: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [Theme.surfaceElevated.opacity(0.7), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                DemoStage(
                    exercise: exercise,
                    fault: selectedFault,
                    view: demoView,
                    isPlaying: isPlaying,
                    speed: speed
                )
                .frame(height: 290)
                .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
            stageControls
        }
        .cardBackground()
        .overlay {
            if let fault = selectedFault, let info = faultInfo(fault) {
                // Cue for the fault being played.
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.coral)
                    Text(info.cue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.ink.opacity(0.9)))
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.snappy(duration: 0.25), value: selectedFault)
    }

    private var stageControls: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.snappy(duration: 0.2)) { isPlaying.toggle() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.inkOnLime)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.lime))
            }
            .accessibilityLabel(isPlaying ? "Pause demo" : "Play demo")

            if ExerciseDemos.views(for: exercise).count > 1 {
                pillToggle(current: demoView.label, options: ExerciseDemos.views(for: exercise).map(\.label)) { newValue in
                    if let v = DemoView(rawValue: newValue.lowercased()) { demoView = v }
                }
            }

            Spacer(minLength: 0)

            if selectedFault != nil {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selectedFault = nil }
                } label: {
                    Label("Clean form", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.lime)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Capsule().fill(Theme.lime.opacity(0.14)))
                }
            }

            pillToggle(current: speed == 1 ? "1×" : "0.5×", options: ["1×", "0.5×"]) { newValue in
                speed = newValue == "1×" ? 1 : 0.5
            }
        }
        .padding(12)
    }

    private func pillToggle(current: String, options: [String], onChange: @escaping (String) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.2)) { onChange(option) }
                } label: {
                    Text(option)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(current == option ? Theme.inkOnLime : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background {
                            if current == option {
                                Capsule().fill(Theme.lime)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.surfaceElevated))
    }

    // MARK: Title

    private var titleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: exercise.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.lime)
            Text(exercise.displayName)
                .font(.display(24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            if exercise.category == .hyrox {
                HyroxTag()
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Standard

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement standard")
                .sectionLabel()
            ForEach(standard, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.lime)
                        .padding(.top, 1)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }

    private var standard: [String] { ExerciseDemos.standard(for: exercise) }

    // MARK: Faults

    private var faultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common faults")
                .sectionLabel()
            ForEach(ExerciseDemos.faults(for: exercise), id: \.key) { fault in
                faultRow(fault)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }

    private func faultRow(_ fault: (key: String, label: String, cue: String)) -> some View {
        let isSelected = selectedFault == fault.key
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedFault = isSelected ? nil : fault.key
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.inkOnLime : Theme.coral)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isSelected ? Theme.coral : Theme.coral.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(fault.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(isSelected ? "Playing — tap to stop" : "Show me")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Theme.coral : Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.coral : Theme.textSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.coral.opacity(0.1) : Theme.surfaceElevated.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Theme.coral.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fault.label). \(fault.cue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func faultInfo(_ key: String) -> (label: String, cue: String)? {
        ExerciseDemos.faults(for: exercise).first { $0.key == key }.map { ($0.label, $0.cue) }
    }

    // MARK: Analyze

    private var analyzeButton: some View {
        Button {
            onAnalyze()
        } label: {
            Label("Analyze my form", systemImage: "camera.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.inkOnLime)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.lime))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint("Opens the camera with \(exercise.displayName) already selected")
    }
}
