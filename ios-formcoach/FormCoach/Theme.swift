//
//  Theme.swift
//  FormCoach
//
//  Design tokens: dark graphite athletic look with a single electric lime accent.
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

enum Theme {
    static let ink = Color(hex: 0x0B0D10)
    static let surface = Color(hex: 0x161B22)
    static let surfaceElevated = Color(hex: 0x1F2530)
    static let stroke = Color.white.opacity(0.07)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x8A93A3)
    static let lime = Color(hex: 0xC6FF3D)
    static let coral = Color(hex: 0xFF6B4A)
    static let inkOnLime = Color(hex: 0x0B0D10)

    static let cardCorner: CGFloat = 16
    static let buttonCorner: CGFloat = 14
    static let margin: CGFloat = 16
}

extension Font {
    /// Monospaced digits for the instrument-panel numbers (scores, counters, timers).
    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    /// Standard elevated card on the ink canvas.
    func cardBackground(cornerRadius: CGFloat = Theme.cardCorner) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    func sectionLabel() -> some View {
        font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .textCase(.uppercase)
            .kerning(0.8)
    }
}
