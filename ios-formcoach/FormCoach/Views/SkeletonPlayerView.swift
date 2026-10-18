//
//  SkeletonPlayerView.swift
//  FormCoach
//
//  Full-screen video player with the tracked skeleton drawn over the user's
//  body, coral flags on the scrubber for problem moments, and a floating
//  coaching caption near flagged times.
//

import SwiftUI
import AVFoundation

struct SkeletonPlayerView: View {
    let videoURL: URL
    let analysis: WorkoutAnalysis

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var isPlaying = true
    @State private var skeletonOn = true
    @State private var duration: Double = 0
    @State private var scrubPreview: Double?
    @State private var endObserver: NSObjectProtocol?

    init(videoURL: URL, analysis: WorkoutAnalysis) {
        self.videoURL = videoURL
        self.analysis = analysis
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                videoArea
                controls
            }

            closeButton
        }
        .statusBarHidden()
        .task { await prepareDuration() }
        .onDisappear {
            player.pause()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        }
    }

    // MARK: - Video + skeleton

    private var videoArea: some View {
        GeometryReader { geo in
            ZStack {
                VideoLayerView(player: player)
                    .allowsHitTesting(false)
                if skeletonOn {
                    PoseOverlay(frames: analysis.frames, videoAspect: analysis.videoAspect, currentTime: currentTime)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 18) {
            captionCard

            FlaggedScrubber(
                duration: duration,
                current: scrubPreview ?? currentTime,
                flags: analysis.flags
            ) { newTime in
                scrubPreview = newTime
            } onCommit: { newTime in
                scrubPreview = nil
                seek(to: newTime)
            }
            .padding(.horizontal, Theme.margin)

            HStack(spacing: 0) {
                Text("\(currentTime.timecode) / \(duration.timecode)")
                    .font(.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(analysis.exercise.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.margin)

            HStack(spacing: 44) {
                skipButton(backward: true)
                playPauseButton
                skipButton(backward: false)
            }
            .frame(maxWidth: .infinity)

            skeletonToggle
                .padding(.bottom, 18)
        }
        .padding(.top, 10)
    }

    private var captionCard: some View {
        Group {
            if let activeFlag {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.coral)
                    Text(activeFlag.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(Theme.surface.opacity(0.94))
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                )
                .padding(.horizontal, Theme.margin)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeFlag)
        .frame(height: 48, alignment: .bottom)
    }

    private var activeFlag: Moment? {
        analysis.flags.first {
            abs(Double($0.time) - currentTime) <= 1.6
        }
    }

    private var closeButton: some View {
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
        }
        .padding(12)
    }

    private var playPauseButton: some View {
        Button {
            togglePlayback()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.inkOnLime)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Theme.lime))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func skipButton(backward: Bool) -> some View {
        Button {
            seek(relative: backward ? -10 : 10)
        } label: {
            Image(systemName: backward ? "gobackward.10" : "goforward.10")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.surface.opacity(0.9)))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var skeletonToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.dance")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(skeletonOn ? Theme.lime : Theme.textSecondary)
            Text("Skeleton \(skeletonOn ? "on" : "off")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Toggle("", isOn: $skeletonOn)
                .labelsHidden()
                .tint(Theme.lime)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Theme.surface.opacity(0.94))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        )
    }

    // MARK: - Playback helpers

    private var currentTime: Double {
        player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= duration - 0.05, duration > 0 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to time: Double) {
        let target = max(0, min(time, duration))
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func seek(relative delta: Double) {
        seek(to: currentTime + delta)
    }

    private func prepareDuration() async {
        if let item = player.currentItem {
            let seconds = (try? await item.asset.load(.duration).seconds) ?? 0
            duration = seconds.isFinite ? seconds : 0
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isPlaying = false
            }
        }
        player.play()
    }
}

// MARK: - Player layer

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVPlayerLayer()
        layer.player = player
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVPlayerLayer {
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - Pose overlay

struct PoseOverlay: View {
    let frames: [PoseFrame]
    let videoAspect: Float
    let currentTime: Double
    /// Joints drawn in coral with a halo — the body part a failed check is about.
    var highlightedJoints: Set<Int> = []
    /// 0–1 phase that breathes the halo around highlighted joints.
    var pulse: Double = 0

    /// Bone connections between joint indices.
    private static let limbs: [(Int, Int)] = [
        (J.neck, J.leftShoulder), (J.neck, J.rightShoulder),
        (J.leftShoulder, J.rightShoulder),
        (J.leftShoulder, J.leftElbow), (J.leftElbow, J.leftWrist),
        (J.rightShoulder, J.rightElbow), (J.rightElbow, J.rightWrist),
        (J.neck, J.root),
        (J.root, J.leftHip), (J.root, J.rightHip),
        (J.leftHip, J.rightHip),
        (J.leftHip, J.leftKnee), (J.leftKnee, J.leftAnkle),
        (J.rightHip, J.rightKnee), (J.rightKnee, J.rightAnkle),
    ]

    var body: some View {
        Canvas { context, size in
            guard !frames.isEmpty else { return }
            let fitted = aspectFitRect(for: size)
            guard let frame = nearestFrame() else { return }

            func map(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: fitted.minX + point.x * fitted.width,
                    y: fitted.minY + (1 - point.y) * fitted.height
                )
            }

            var bones = Path()
            for (a, b) in Self.limbs {
                guard let pa = frame.pt(a), let pb = frame.pt(b) else { continue }
                bones.move(to: map(pa))
                bones.addLine(to: map(pb))
            }
            context.stroke(
                bones,
                with: .color(highlightedJoints.isEmpty ? Theme.lime : Theme.lime.opacity(0.55)),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

            // Bones touching a flagged joint turn coral so the problem area reads at a glance.
            if !highlightedJoints.isEmpty {
                var hot = Path()
                for (a, b) in Self.limbs where highlightedJoints.contains(a) || highlightedJoints.contains(b) {
                    guard let pa = frame.pt(a), let pb = frame.pt(b) else { continue }
                    hot.move(to: map(pa))
                    hot.addLine(to: map(pb))
                }
                context.stroke(
                    hot,
                    with: .color(Theme.coral),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
            }

            for index in 0..<15 where frame.points.indices.contains(index) {
                guard let point = frame.pt(index) else { continue }
                let center = map(point)
                if highlightedJoints.contains(index) {
                    let haloRadius = 16 + 8 * pulse
                    let halo = CGRect(x: center.x - haloRadius, y: center.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
                    context.fill(Path(ellipseIn: halo), with: .color(Theme.coral.opacity(0.35 * (1 - pulse * 0.6))))
                    context.stroke(Path(ellipseIn: halo), with: .color(Theme.coral.opacity(0.8)), lineWidth: 2)
                    let dot = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
                    context.fill(Path(ellipseIn: dot), with: .color(Theme.coral))
                    context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 2)
                } else {
                    let rect = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.lime))
                }
            }
        }
    }

    private func nearestFrame() -> PoseFrame? {
        var best: PoseFrame?
        var bestDelta = Double.greatestFiniteMagnitude
        for frame in frames {
            let delta = abs(Double(frame.time) - currentTime)
            if delta < bestDelta {
                bestDelta = delta
                best = frame
            }
        }
        return best
    }

    private func aspectFitRect(for size: CGSize) -> CGRect {
        guard videoAspect > 0 else { return CGRect(origin: .zero, size: size) }
        let viewAspect = size.width / size.height
        if CGFloat(videoAspect) > viewAspect {
            let height = size.width / CGFloat(videoAspect)
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        } else {
            let width = size.height * CGFloat(videoAspect)
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
    }
}

// MARK: - Flagged scrubber

struct FlaggedScrubber: View {
    let duration: Double
    let current: Double
    let flags: [Moment]
    let onPreview: (Double) -> Void
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = duration > 0 ? current / duration : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceElevated)
                    .frame(height: 6)
                Capsule()
                    .fill(Theme.lime)
                    .frame(width: max(0, width * fraction), height: 6)
                ForEach(flags.indices, id: \.self) { index in
                    let flag = flags[index]
                    Circle()
                        .fill(Theme.coral)
                        .frame(width: 10, height: 10)
                        .position(x: width * (Double(flag.time) / max(duration, 0.001)), y: geo.size.height / 2)
                }
                Circle()
                    .fill(Theme.textPrimary)
                    .frame(width: 18, height: 18)
                    .position(x: width * fraction, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / width))
                        onPreview(fraction * duration)
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / width))
                        onCommit(fraction * duration)
                    }
            )
        }
        .frame(height: 26)
    }
}

private extension Double {
    var timecode: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
