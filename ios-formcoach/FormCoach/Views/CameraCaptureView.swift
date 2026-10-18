//
//  CameraCaptureView.swift
//  FormCoach
//
//  Full-screen camera for filming a workout clip: viewfinder with a live level
//  (green when the phone is upright and steady), a record flow that waits for
//  steady and counts down, filming tip, and clean states for missing camera or
//  denied access.
//

import SwiftUI

struct CameraCaptureView: View {
    /// Called with the recorded clip; the caller dismisses and starts the analyze flow.
    var onFinish: (URL) -> Void
    /// Called when the user backs out without a recording.
    var onClose: () -> Void
    /// Offered when filming isn't possible, so the library is one tap away.
    /// Nil hides the option (e.g. when opened from the Library tab).
    var onPickFromLibrary: (() -> Void)? = nil

    /// Pre-record flow: idle, waiting for the phone to steady, or counting down.
    private enum Phase: Equatable {
        case idle
        case waiting
        case countdown(Int)
    }

    @State private var recorder = CameraRecorder()
    @State private var level = LevelMonitor()
    @State private var phase: Phase = .idle
    @State private var showStartAnyway = false
    @State private var flowTask: Task<Void, Never>?
    /// The just-recorded clip, shown in the trim step before analysis.
    @State private var recordedURL: URL?

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            switch recorder.availability {
            case .checking:
                ProgressView().tint(Theme.lime)
            case .ready:
                CameraPreviewView(session: recorder.session)
                    .ignoresSafeArea()
                    .overlay { countdownOverlay }
                    .overlay(alignment: .bottom) { controls.ignoresSafeArea(edges: .bottom) }
                    .overlay(alignment: .top) { topBar }
            case .unauthorized:
                deniedState
            case .unavailable:
                unavailableState
            }

            if let recordedURL {
                ClipTrimView(
                    videoURL: recordedURL,
                    onUse: onFinish,
                    onRetake: {
                        try? FileManager.default.removeItem(at: recordedURL)
                        withAnimation(.snappy(duration: 0.3)) { self.recordedURL = nil }
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .statusBarHidden()
        .task {
            recorder.onFinish = { url in
                withAnimation(.snappy(duration: 0.3)) { recordedURL = url }
            }
            await recorder.start()
            level.start()
        }
        .onDisappear {
            flowTask?.cancel()
            level.stop()
            recorder.shutdown()
        }
        .onChange(of: level.isLevel) { _, isLevel in
            // A light tap the moment the phone locks in, so it's felt, not watched.
            if isLevel, phase == .waiting {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    // MARK: - Ready state

    private var topBar: some View {
        HStack {
            circleButton("xmark", action: onClose)
            Spacer()
            circleButton("arrow.triangle.2.circlepath.camera", action: recorder.flipCamera)
                .disabled(recorder.isRecording)
                .opacity(recorder.isRecording ? 0.4 : 1)
        }
        .padding(.horizontal, 12)
    }

    private var controls: some View {
        VStack(spacing: 20) {
            // Filming tip
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                Text("Film your whole body from the side, and keep the phone still.")
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(0.45))
            )
            .padding(.horizontal, 24)

            VStack(spacing: 14) {
                if recorder.isRecording {
                    Text(timeLabel(recorder.elapsed))
                        .font(.mono(22, weight: .bold))
                        .foregroundStyle(Theme.coral)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if !recorder.isRecording {
                    levelBar
                }
                recordButton
                statusCaption
            }
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.25), value: recorder.isRecording)
        }
    }

    /// Current guidance line under the record button.
    @ViewBuilder
    private var statusCaption: some View {
        if recorder.isRecording {
            Text("Stops automatically at 5:00")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        } else if phase == .waiting {
            VStack(spacing: 6) {
                Text("Waiting for steady…")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                if showStartAnyway {
                    Button("Start anyway") { startAnyway() }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.lime)
                }
            }
        }
    }

    // MARK: - Level

    /// Slim bar with a center notch; the dot glides with the phone's lean and
    /// settles into the notch, turning lime, when the phone is upright and steady.
    private var levelBar: some View {
        let fraction = max(-1, min(1, level.rollDegrees / LevelMonitor.fullScaleRoll))
        let dotOffset: CGFloat = level.isLevel ? 0 : CGFloat(fraction) * 100
        return VStack(spacing: 8) {
            ZStack {
                Capsule()
                    .fill(.black.opacity(0.5))
                    .frame(width: 220, height: 6)
                Rectangle()
                    .fill(Theme.textSecondary.opacity(0.8))
                    .frame(width: 2, height: 14)
                Circle()
                    .fill(level.isLevel ? Theme.lime : Theme.coral)
                    .frame(width: 16, height: 16)
                    .shadow(color: level.isLevel ? Theme.lime.opacity(0.6) : .clear, radius: 6)
                    .offset(x: dotOffset)
            }
            Text(level.isLevel ? "Steady" : "Hold your phone upright")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(level.isLevel ? Theme.lime : Theme.textSecondary)
        }
        .animation(.snappy(duration: 0.2), value: level.isLevel)
        .animation(.snappy(duration: 0.2), value: level.rollDegrees)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(level.isLevel ? "Phone is level" : "Phone is not level")
    }

    // MARK: - Record flow

    @ViewBuilder
    private var countdownOverlay: some View {
        if case .countdown(let beat) = phase {
            Text("\(beat)")
                .font(.mono(110, weight: .heavy))
                .foregroundStyle(Theme.lime)
                .shadow(color: .black.opacity(0.5), radius: 12)
                .id(beat)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
                .animation(.spring(duration: 0.45), value: beat)
        }
    }

    private var recordButton: some View {
        Button {
            recordTapped()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Theme.lime, lineWidth: 4)
                    .frame(width: 78, height: 78)
                if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.coral)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(Theme.lime)
                        .frame(width: 62, height: 62)
                }
            }
            .frame(width: 78, height: 78)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
    }

    private func recordTapped() {
        if recorder.isRecording {
            recorder.stopRecording()
        } else if phase == .waiting {
            startAnyway()
        } else {
            beginCountdown()
        }
    }

    /// Counts down from 3, pausing if the phone drifts off-level mid-count.
    private func beginCountdown() {
        flowTask?.cancel()
        showStartAnyway = false
        phase = .countdown(3)
        flowTask = Task {
            for beat in [3, 2, 1] {
                guard level.isLevel else { beginWaiting(); return }
                withAnimation(.spring(duration: 0.45)) { phase = .countdown(beat) }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard level.isLevel else { beginWaiting(); return }
            phase = .idle
            recorder.startRecording()
        }
    }

    /// Waits for the level to go green, with a "Start anyway" escape after 5 s
    /// so an awkwardly propped phone never blocks filming.
    private func beginWaiting() {
        flowTask?.cancel()
        showStartAnyway = false
        phase = .waiting
        flowTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled, phase == .waiting {
                withAnimation(.snappy(duration: 0.25)) { showStartAnyway = true }
            }
        }
    }

    private func startAnyway() {
        flowTask?.cancel()
        phase = .idle
        recorder.startRecording()
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.black.opacity(0.55)))
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: - Problem states

    private var deniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 38))
                .foregroundStyle(Theme.textSecondary)
            Text("Camera access is off")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("FormCoach needs the camera to film your workout. You can enable it in Settings, or pick a video you already recorded.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.inkOnLime)
                    .padding(.horizontal, 28)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.lime))
            }
            .buttonStyle(PressableButtonStyle())
            if onPickFromLibrary != nil { libraryButton }
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 38))
                .foregroundStyle(Theme.textSecondary)
            Text("No camera available")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("There's no camera to film with here. Choose a workout video from your library instead.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if onPickFromLibrary != nil { libraryButton }
        }
    }

    private var libraryButton: some View {
        Button {
            onClose()
            onPickFromLibrary?()
        } label: {
            Text("Choose from library")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 28)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.surfaceElevated))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
