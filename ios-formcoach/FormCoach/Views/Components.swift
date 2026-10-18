//
//  Components.swift
//  FormCoach
//
//  Shared views: score ring, rep bars, stat tiles, week strip, video thumbnails.
//

import SwiftUI
import AVFoundation

// MARK: - Score Ring

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 120
    var lineWidth: CGFloat = 10

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surfaceElevated, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.mono(size * 0.36))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("/100")
                    .font(.mono(size * 0.13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            progress = 0
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.15)) {
                progress = CGFloat(score) / 100
            }
        }
    }
}

// MARK: - Stat Tile

struct StatTile: View {
    let icon: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.surfaceElevated))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.mono(24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .cardBackground()
    }
}

// MARK: - Week Strip

struct WeekStrip: View {
    /// Total reps per weekday, Monday-first (nil = no workout that day).
    let dayTotals: [Double?]

    private static let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This week")
                .sectionLabel()
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    DayBar(label: Self.dayLabels[index], value: dayTotals[index], maxValue: maxima)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110)
        }
        .padding(16)
        .cardBackground()
    }

    private var maxima: Double {
        dayTotals.compactMap { $0 }.max() ?? 0
    }
}

private struct DayBar: View {
    let label: String
    let value: Double?
    let maxValue: Double

    @State private var animatedHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Theme.surfaceElevated)
                    .frame(width: 18, height: 88)
                Capsule()
                    .fill(Theme.lime)
                    .frame(width: 18, height: animatedHeight)
            }
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .onAppear {
            guard let value, maxValue > 0 else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.1)) {
                animatedHeight = max(10, 88 * CGFloat(value / maxValue))
            }
        }
    }
}

// MARK: - Rep Bars

struct RepBars: View {
    let reps: [RepResult]
    let exercise: Exercise

    @State private var appeared = false

    private var title: String {
        exercise.isHold ? "Hold" : "\(exercise.unitSingular.capitalized) scores"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .sectionLabel()
                Spacer(minLength: 0)
                if reps.count > 12 {
                    Text("\(reps.count) \(exercise.unitSingular)s")
                        .font(.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ScoreBarChart(reps: reps, barAreaHeight: 96, maxBarWidth: 20, appeared: appeared) { rep in
                exercise.isHold ? "•" : "\(rep.id)"
            }
            .frame(height: 120)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) {
                appeared = true
            }
        }
    }
}

/// Per-rep score bars that thin out for long sets (e.g. 100 wall balls) and
/// label every Nth bar so text never collides.
struct ScoreBarChart: View {
    let reps: [RepResult]
    let barAreaHeight: CGFloat
    let maxBarWidth: CGFloat
    let appeared: Bool
    let label: (RepResult) -> String

    var body: some View {
        GeometryReader { geo in
            let count = max(reps.count, 1)
            let slot = geo.size.width / CGFloat(count)
            let barWidth = min(maxBarWidth, max(3, slot * 0.62))
            let labelStride = max(1, Int((24 / slot).rounded(.up)))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(reps) { rep in
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Theme.surfaceElevated)
                                .frame(width: barWidth, height: barAreaHeight)
                            Capsule()
                                .fill(rep.score < 60 ? Theme.coral : Theme.lime)
                                .frame(width: barWidth, height: appeared ? max(min(12, barAreaHeight), barAreaHeight * CGFloat(rep.score) / 100) : 0)
                        }
                        Text((rep.id - 1) % labelStride == 0 ? label(rep) : " ")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: slot)
                    }
                    .frame(width: slot)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(label(rep)): \(rep.score) points")
                }
            }
        }
    }
}

/// Small outlined badge marking HYROX sessions.
struct HyroxTag: View {
    var body: some View {
        Text("HYROX")
            .font(.system(size: 9, weight: .heavy))
            .kerning(0.8)
            .foregroundStyle(Theme.lime)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.lime.opacity(0.6), lineWidth: 1)
            )
    }
}

// MARK: - Swipe to Delete

/// Wraps a row with a coral delete background revealed by swiping left.
/// Past the trigger distance the row slides out and `onDelete` fires.
struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0

    private let triggerDistance: CGFloat = 80

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(Theme.coral)
                .overlay(alignment: .trailing) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.trailing, 28)
                        .opacity(min(1, -dragOffset / triggerDistance))
                }
                .opacity(dragOffset < -4 ? 1 : 0)

            content()
                .offset(x: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            let translation = value.translation.width
                            dragOffset = min(0, translation)
                        }
                        .onEnded { value in
                            if value.translation.width < -triggerDistance {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    dragOffset = -640
                                }
                                Task {
                                    try? await Task.sleep(for: .seconds(0.2))
                                    onDelete()
                                }
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        }
    }
}

// MARK: - Video Thumbnail

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, UIImage>()

    func thumbnail(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = await Self.generate(url: url)
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    @concurrent
    nonisolated private static func generate(url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let cgImage = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

struct VideoThumb: View {
    let url: URL?
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?

    var body: some View {
        Color(Theme.surfaceElevated)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .task(id: url) {
                image = await ThumbnailCache.shared.thumbnail(for: url)
            }
    }
}
