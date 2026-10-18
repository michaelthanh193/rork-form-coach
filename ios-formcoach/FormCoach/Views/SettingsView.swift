//
//  SettingsView.swift
//  FormCoach
//
//  Settings tab: how strictly camera movement is flagged, plus the on-device
//  privacy note.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("cameraMotionSensitivity") private var sensitivityRaw = MotionSensitivity.default.rawValue

    private var sensitivity: MotionSensitivity {
        MotionSensitivity(rawValue: sensitivityRaw) ?? .default
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sensitivityCard
                privacyCard
            }
            .padding(Theme.margin)
            .padding(.bottom, 24)
        }
        .background(Theme.ink)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Camera movement

    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Camera movement")
                    .sectionLabel()
                Text("How readily shaky footage gets flagged and its distance checks skipped.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(MotionSensitivity.allCases, id: \.self) { option in
                    segmentButton(option)
                }
            }

            Text(sensitivity.explanation)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.snappy(duration: 0.2), value: sensitivity)
                .accessibilityLabel("Sensitivity: \(sensitivity.label). \(sensitivity.explanation)")
        }
        .padding(16)
        .cardBackground()
    }

    private func segmentButton(_ option: MotionSensitivity) -> some View {
        let isSelected = option == sensitivity
        return Button {
            withAnimation(.snappy(duration: 0.2)) { sensitivityRaw = option.rawValue }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(option.label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isSelected ? Theme.inkOnLime : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Theme.lime : Theme.surfaceElevated)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Privacy

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.lime)
                Text("Private by design")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Every video is analyzed right on this iPhone — nothing is uploaded, ever.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Theme.stroke)
            Text("FormCoach · Version 1.0")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}
