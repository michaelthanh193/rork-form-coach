//
//  FormReportView.swift
//  FormCoach
//
//  The coaching report: score ring, rep breakdown, strengths, fixes,
//  and a button to replay the video with the skeleton overlay.
//

import SwiftUI

struct FormReportView: View {
    let session: WorkoutSession

    @AppStorage("cameraMotionSensitivity") private var sensitivityRaw = MotionSensitivity.default.rawValue
    @State private var showPlayer = false
    @State private var showFlaggedMoments = false

    private var analysis: WorkoutAnalysis? { session.analysis }

    /// The analysis re-judged under the current sensitivity: shaky footage that
    /// wasn't corrected loses its distance-based faults and rescores here.
    private var resolved: WorkoutAnalysis? {
        analysis.map { FormEvaluator.resolve($0, sensitivity: sensitivity) }
    }

    private var sensitivity: MotionSensitivity {
        MotionSensitivity(rawValue: sensitivityRaw) ?? .default
    }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            if let analysis = resolved {
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard(analysis)
                        if let banner = motionBanner(for: analysis) {
                            motionBannerView(banner)
                        }
                        repScoreCard(analysis)
                        strengthsCard(analysis)
                        fixesCard(analysis)
                        if session.videoURL != nil, !analysis.flags.isEmpty {
                            flaggedMomentsButton(count: analysis.flags.count)
                        }
                    }
                    .padding(Theme.margin)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                Text("This report is unavailable.")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle("Form Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if session.videoURL != nil, resolved != nil {
                replayButton
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = session.videoURL, let analysis = resolved {
                SkeletonPlayerView(videoURL: url, analysis: analysis)
            }
        }
        .fullScreenCover(isPresented: $showFlaggedMoments) {
            if let url = session.videoURL, let analysis = resolved {
                FlaggedMomentsView(videoURL: url, analysis: analysis)
            }
        }
    }

    // MARK: - Flagged moments

    /// Opens the step-through of every frame where a check failed.
    private func flaggedMomentsButton(count: Int) -> some View {
        Button {
            showFlaggedMoments = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.coral)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.coral.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replay flagged moments")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("See each frame where a check failed")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.mono(17, weight: .bold))
                    .foregroundStyle(Theme.coral)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .cardBackground()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Replay \(count) flagged moments")
    }

    // MARK: - Header

    private func headerCard(_ analysis: WorkoutAnalysis) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(session.exercise.displayName) · \(session.date.shortDayMonth)")
                    .font(.display(24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(summaryLine(analysis))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if session.exercise.category == .hyrox {
                    HyroxTag()
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            ScoreRing(score: analysis.overallScore, size: 92, lineWidth: 9)
        }
        .padding(16)
        .cardBackground()
    }

    private func summaryLine(_ analysis: WorkoutAnalysis) -> String {
        let seconds = "\(Int(analysis.duration.rounded())) sec"
        if session.exercise.isHold { return "\(analysis.tempoLabel) · \(seconds)" }
        return "\(session.exercise.countLabel(session.repCount)) · \(analysis.tempoLabel) · \(seconds)"
    }

    // MARK: - Camera banner

    private struct MotionBanner {
        let isWarning: Bool
        let icon: String
        let title: String
        let message: String
    }

    /// What the report says about camera movement, judged at the current
    /// sensitivity: corrected clips get an all-clear, uncorrected ones name the
    /// skipped checks and the reason.
    private func motionBanner(for analysis: WorkoutAnalysis) -> MotionBanner? {
        guard let motion = analysis.cameraMotion,
              motion.isUnstable(threshold: sensitivity.threshold) else { return nil }
        if motion.corrected == true {
            return MotionBanner(
                isWarning: false,
                icon: "wand.and.rays",
                title: "Camera steadied",
                message: "The camera moved during this clip, but FormCoach corrected for it — every check ran on steadied footage."
            )
        }
        let skipped = FormEvaluator.distanceCheckLabels(for: analysis.exercise)
        guard !skipped.isEmpty else { return nil }
        return MotionBanner(
            isWarning: true,
            icon: "exclamationmark.triangle.fill",
            title: "Camera was moving",
            message: "Skipped: \(listed(skipped)). The camera moved too much to correct, so those numbers weren't reliable. Prop your phone up next time."
        )
    }

    private func listed(_ items: [String]) -> String {
        switch items.count {
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    /// Coral when checks were skipped, a calm lime all-clear when correction ran.
    private func motionBannerView(_ banner: MotionBanner) -> some View {
        let tint = banner.isWarning ? Theme.coral : Theme.lime
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(banner.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(tint.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Rep scores

    private func repScoreCard(_ analysis: WorkoutAnalysis) -> some View {
        RepBars(reps: analysis.reps, exercise: session.exercise)
            .padding(16)
            .cardBackground()
    }

    // MARK: - Strengths

    private func strengthsCard(_ analysis: WorkoutAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you did well")
                .sectionLabel()
            if analysis.strengths.isEmpty {
                Text("We'll highlight your strengths here as your reps get consistent.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(analysis.strengths) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.lime)
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    if item.id != analysis.strengths.last?.id {
                        Divider().overlay(Theme.stroke)
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Fixes

    private func fixesCard(_ analysis: WorkoutAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fix these")
                .sectionLabel()
            if analysis.fixes.isEmpty {
                Text("Textbook form — nothing to fix. Add weight or reps and check back.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(analysis.fixes) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Theme.coral)
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    if item.id != analysis.fixes.last?.id {
                        Divider().overlay(Theme.stroke)
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Replay

    private var replayButton: some View {
        Button {
            showPlayer = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Replay with skeleton")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(Theme.inkOnLime)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(Theme.lime)
            )
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private extension Date {
    var shortDayMonth: String {
        formatted(.dateTime.month(.abbreviated).day())
    }
}
