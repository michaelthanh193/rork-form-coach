//
//  ClipTrimView.swift
//  FormCoach
//
//  Trim step shown right after recording: a filmstrip with lime start/end
//  handles to select just the working set, a preview that loops the selected
//  range, and "Use clip" which exports only that range for analysis.
//

import SwiftUI
import AVFoundation
import UIKit

struct ClipTrimView: View {
    let videoURL: URL
    /// Called with the clip to analyze — the trimmed export, or the original if untouched.
    var onUse: (URL) -> Void
    /// Throws the recording away and goes back to the viewfinder.
    var onRetake: () -> Void

    @State private var player: AVPlayer
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var thumbnails: [UIImage] = []
    @State private var isExporting = false
    @State private var exportFailed = false
    @State private var loopTask: Task<Void, Never>?
    @State private var playhead: Double = 0
    @State private var confirmDiscard = false

    /// Shortest selection allowed — anything less can't hold a rep.
    private let minimumLength: Double = 1.5
    private let handleWidth: CGFloat = 18
    private let stripHeight: CGFloat = 60

    init(videoURL: URL, onUse: @escaping (URL) -> Void, onRetake: @escaping () -> Void) {
        self.videoURL = videoURL
        self.onUse = onUse
        self.onRetake = onRetake
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 18) {
                header
                VideoLayerView(player: player)
                    .clipShape(.rect(cornerRadius: Theme.cardCorner))
                    .padding(.horizontal, Theme.margin)
                    .allowsHitTesting(false)
                rangeLabels
                trimStrip
                    .padding(.horizontal, Theme.margin)
                Text("Drag the handles so only your working set is left.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                actions
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .statusBarHidden()
        .task { await prepare() }
        .onDisappear {
            loopTask?.cancel()
            player.pause()
        }
        .alert("Couldn't trim the clip", isPresented: $exportFailed) {
            Button("Use full clip") { onUse(videoURL) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can analyze the whole recording instead.")
        }
        .alert("Discard this recording?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { onRetake() }
            Button("Keep editing", role: .cancel) { restartLoop() }
        } message: {
            Text("Your clip will be deleted and you'll go back to the camera.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Trim your set")
                .font(.display(22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text((end - start).durationLabel)
                .font(.mono(15, weight: .bold))
                .foregroundStyle(Theme.lime)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: Int((end - start) * 10))
        }
        .padding(.horizontal, Theme.margin)
    }

    private var rangeLabels: some View {
        HStack {
            label(title: "Start", value: start)
            Spacer()
            label(title: "End", value: end)
        }
        .padding(.horizontal, Theme.margin)
    }

    private func label(title: String, value: Double) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .sectionLabel()
            Text(value.preciseTimecode)
                .font(.mono(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: - Filmstrip with handles

    private var trimStrip: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width - handleWidth * 2
            let startX = position(for: start, trackWidth: trackWidth)
            let endX = position(for: end, trackWidth: trackWidth)

            ZStack(alignment: .leading) {
                // Filmstrip
                HStack(spacing: 0) {
                    ForEach(thumbnails.indices, id: \.self) { index in
                        Theme.surfaceElevated
                            .overlay {
                                Image(uiImage: thumbnails[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            }
                            .clipped()
                    }
                }
                .frame(width: trackWidth, height: stripHeight)
                .background(Theme.surfaceElevated)
                .clipShape(.rect(cornerRadius: 6))
                .offset(x: handleWidth)

                // Dim everything outside the selection
                Rectangle()
                    .fill(.black.opacity(0.6))
                    .frame(width: max(0, startX - handleWidth), height: stripHeight)
                    .offset(x: handleWidth)
                Rectangle()
                    .fill(.black.opacity(0.6))
                    .frame(width: max(0, trackWidth + handleWidth - endX), height: stripHeight)
                    .offset(x: endX)

                // Selection frame
                Rectangle()
                    .strokeBorder(Theme.lime, lineWidth: 3)
                    .frame(width: max(0, endX - startX), height: stripHeight)
                    .offset(x: startX)

                // Playhead
                if duration > 0 {
                    Capsule()
                        .fill(Theme.textPrimary)
                        .frame(width: 3, height: stripHeight + 10)
                        .offset(x: position(for: playhead, trackWidth: trackWidth) - 1.5)
                        .allowsHitTesting(false)
                }

                handle(isStart: true)
                    .offset(x: startX - handleWidth)
                    .gesture(dragGesture(isStart: true, trackWidth: trackWidth))
                handle(isStart: false)
                    .offset(x: endX)
                    .gesture(dragGesture(isStart: false, trackWidth: trackWidth))
            }
            .coordinateSpace(name: "trimStrip")
        }
        .frame(height: stripHeight + 10)
    }

    private func handle(isStart: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: isStart ? 8 : 0,
            bottomLeadingRadius: isStart ? 8 : 0,
            bottomTrailingRadius: isStart ? 0 : 8,
            topTrailingRadius: isStart ? 0 : 8,
            style: .continuous
        )
        .fill(Theme.lime)
        .frame(width: handleWidth, height: stripHeight)
        .overlay {
            Capsule()
                .fill(Theme.inkOnLime)
                .frame(width: 3, height: 20)
        }
        // A wider invisible hit area so handles are easy to grab.
        .frame(width: 44, height: stripHeight + 10)
        .contentShape(Rectangle())
        .offset(x: -13)
        .accessibilityElement()
        .accessibilityLabel(isStart ? "Start handle" : "End handle")
        .accessibilityValue((isStart ? start : end).preciseTimecode)
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.5 : -0.5
            if isStart { setStart(start + step) } else { setEnd(end + step) }
            restartLoop()
        }
    }

    private func dragGesture(isStart: Bool, trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("trimStrip"))
            .onChanged { value in
                // The finger sits on the handle, half a handle outside the selection edge.
                let x = value.location.x + (isStart ? handleWidth / 2 : -handleWidth / 2)
                let time = time(for: x, trackWidth: trackWidth)
                loopTask?.cancel()
                player.pause()
                if isStart { setStart(time) } else { setEnd(time) }
                let preview = isStart ? start : end
                playhead = preview
                player.seek(to: CMTime(seconds: preview, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            .onEnded { _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                restartLoop()
            }
    }

    private func setStart(_ value: Double) {
        let clamped = max(0, min(value, end - minimumLength))
        if Int(clamped * 10) != Int(start * 10) { UISelectionFeedbackGenerator().selectionChanged() }
        start = clamped
    }

    private func setEnd(_ value: Double) {
        let clamped = min(duration, max(value, start + minimumLength))
        if Int(clamped * 10) != Int(end * 10) { UISelectionFeedbackGenerator().selectionChanged() }
        end = clamped
    }

    private func position(for time: Double, trackWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return handleWidth }
        return handleWidth + CGFloat(time / duration) * trackWidth
    }

    private func time(for x: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return 0 }
        let fraction = Double(max(0, min(1, (x - handleWidth) / trackWidth)))
        return fraction * duration
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                loopTask?.cancel()
                player.pause()
                confirmDiscard = true
            } label: {
                Text("Retake")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.surfaceElevated))
            }
            .buttonStyle(PressableButtonStyle())

            Button {
                Task { await useClip() }
            } label: {
                HStack(spacing: 8) {
                    if isExporting {
                        ProgressView().tint(Theme.inkOnLime)
                    }
                    Text(isExporting ? "Trimming…" : "Use clip")
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.inkOnLime)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.lime))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isExporting || duration == 0)
        }
        .padding(.horizontal, Theme.margin)
    }

    // MARK: - Loading, looping, export

    private func prepare() async {
        let asset = AVURLAsset(url: videoURL)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        guard seconds.isFinite, seconds > 0 else { return }
        duration = seconds
        end = seconds
        restartLoop()
        await loadThumbnails(asset: asset)
    }

    private func loadThumbnails(asset: AVURLAsset) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let count = 10
        var images: [UIImage] = []
        for index in 0..<count {
            let time = CMTime(seconds: duration * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
            if let result = try? await generator.image(at: time) {
                images.append(UIImage(cgImage: result.image))
            }
        }
        withAnimation(.easeOut(duration: 0.25)) { thumbnails = images }
    }

    /// Plays the selected range on repeat so you can see exactly what will be analyzed.
    /// Always begins from the start handle, so releasing either handle replays the cut-in point.
    private func restartLoop() {
        loopTask?.cancel()
        player.pause()
        player.isMuted = true
        playhead = start
        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        loopTask = Task {
            // Wait for the seek to land so the loop never reads the old drag position.
            _ = await player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled else { return }
            player.play()
            while !Task.isCancelled {
                let now = player.currentTime().seconds
                if now.isFinite {
                    playhead = now
                    if now >= end - 0.05 || player.timeControlStatus == .paused {
                        _ = await player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        player.play()
                    }
                }
                try? await Task.sleep(for: .seconds(0.05))
            }
        }
    }

    private func useClip() async {
        loopTask?.cancel()
        player.pause()
        // Untouched selection: no need to re-export.
        if start < 0.1, end > duration - 0.1 {
            onUse(videoURL)
            return
        }
        isExporting = true
        defer { isExporting = false }

        let asset = AVURLAsset(url: videoURL)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            exportFailed = true
            return
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        do {
            try await session.export(to: output, as: .mov)
            try? FileManager.default.removeItem(at: videoURL)
            onUse(output)
        } catch {
            exportFailed = true
        }
    }
}

private extension Double {
    /// "0:07.4" — tenths matter when trimming.
    var preciseTimecode: String {
        let clamped = max(0, self)
        let minutes = Int(clamped) / 60
        let seconds = clamped - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }

    var durationLabel: String {
        String(format: "%.1f sec", max(0, self))
    }
}
