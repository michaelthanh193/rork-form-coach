//
//  FlaggedMomentsView.swift
//  FormCoach
//
//  Steps through every moment where a check failed: the video freezes on that
//  frame, the skeleton is drawn over it, and the joints behind the fault glow
//  coral. Auto-advances like a slideshow, with prev/next and swipe.
//

import SwiftUI
import AVFoundation

struct FlaggedMomentsView: View {
    let videoURL: URL
    let analysis: WorkoutAnalysis

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var index = 0
    @State private var isCycling = true
    @State private var cycleTask: Task<Void, Never>?
    @State private var cycleProgress: Double = 0

    /// Seconds each moment stays on screen while auto-cycling.
    private let holdDuration: Double = 3.5

    init(videoURL: URL, analysis: WorkoutAnalysis) {
        self.videoURL = videoURL
        self.analysis = analysis
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    private var moments: [Moment] { analysis.flags }

    private var current: Moment? {
        moments.indices.contains(index) ? moments[index] : nil
    }

    private var highlighted: Set<Int> {
        guard let current, let fault = FormEvaluator.faultKey(for: current) else { return [] }
        return FaultJoints.joints(for: fault, exercise: analysis.exercise)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                videoArea
                controls
            }

            topBar
        }
        .statusBarHidden()
        .onAppear {
            player.isMuted = true
            showMoment(at: 0)
            startCycling()
        }
        .onDisappear {
            cycleTask?.cancel()
            player.pause()
        }
    }

    // MARK: - Frozen frame + skeleton

    private var videoArea: some View {
        ZStack {
            VideoLayerView(player: player)
                .allowsHitTesting(false)
            if let current {
                TimelineView(.animation) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                    PoseOverlay(
                        frames: analysis.frames,
                        videoAspect: analysis.videoAspect,
                        currentTime: Double(current.time),
                        highlightedJoints: highlighted,
                        pulse: (sin(phase * 2 * .pi) + 1) / 2
                    )
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40 { step(1, manual: true) }
                    if value.translation.width > 40 { step(-1, manual: true) }
                }
        )
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.14)))
            }
            Spacer()
            if !moments.isEmpty {
                Text("\(index + 1) / \(moments.count)")
                    .font(.mono(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Capsule().fill(.white.opacity(0.14)))
                    .animation(.snappy, value: index)
            }
        }
        .padding(12)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            captionCard
            momentTicks
                .padding(.horizontal, Theme.margin)
            HStack(spacing: 44) {
                stepButton(forward: false)
                cycleButton
                stepButton(forward: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
        }
        .padding(.top, 12)
    }

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let current {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.coral)
                    Text(current.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(Double(current.time).timecode)
                        .font(.mono(13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                .id(index)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .strokeBorder(Theme.coral.opacity(0.35), lineWidth: 1)
                )
        )
        .clipped()
        .padding(.horizontal, Theme.margin)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
        .accessibilityElement(children: .combine)
    }

    /// One segment per moment; the current one fills lime as the slideshow advances.
    private var momentTicks: some View {
        HStack(spacing: 4) {
            ForEach(moments.indices, id: \.self) { tick in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceElevated)
                        Capsule()
                            .fill(tick < index ? Theme.coral : Theme.lime)
                            .frame(width: geo.size.width * fill(for: tick))
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func fill(for tick: Int) -> Double {
        if tick < index { return 1 }
        if tick > index { return 0 }
        return isCycling ? cycleProgress : 1
    }

    private func stepButton(forward: Bool) -> some View {
        Button {
            step(forward ? 1 : -1, manual: true)
        } label: {
            Image(systemName: forward ? "forward.end.fill" : "backward.end.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.surface.opacity(0.9)))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(forward ? index >= moments.count - 1 : index == 0)
        .opacity((forward ? index >= moments.count - 1 : index == 0) ? 0.4 : 1)
        .accessibilityLabel(forward ? "Next moment" : "Previous moment")
    }

    private var cycleButton: some View {
        Button {
            if isCycling {
                stopCycling()
            } else {
                if index >= moments.count - 1 { showMoment(at: 0) }
                startCycling()
            }
        } label: {
            Image(systemName: isCycling ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.inkOnLime)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Theme.lime))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(isCycling ? "Pause slideshow" : "Play slideshow")
    }

    // MARK: - Navigation

    private func showMoment(at newIndex: Int) {
        guard moments.indices.contains(newIndex) else { return }
        withAnimation(.snappy) { index = newIndex }
        let time = CMTime(seconds: Double(moments[newIndex].time), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func step(_ delta: Int, manual: Bool) {
        let target = index + delta
        guard moments.indices.contains(target) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showMoment(at: target)
        if manual, isCycling { startCycling() }
    }

    private func startCycling() {
        cycleTask?.cancel()
        isCycling = true
        cycleProgress = 0
        cycleTask = Task {
            while !Task.isCancelled {
                let tick = 0.05
                var elapsed: Double = 0
                while elapsed < holdDuration {
                    try? await Task.sleep(for: .seconds(tick))
                    if Task.isCancelled { return }
                    elapsed += tick
                    cycleProgress = min(1, elapsed / holdDuration)
                }
                if index >= moments.count - 1 {
                    isCycling = false
                    return
                }
                cycleProgress = 0
                step(1, manual: false)
            }
        }
    }

    private func stopCycling() {
        cycleTask?.cancel()
        isCycling = false
    }
}

private extension Double {
    var timecode: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
