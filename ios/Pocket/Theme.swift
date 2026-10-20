import SwiftUI

// MARK: - Palette (mirrors the DSH design tokens, dark theme)

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Theme {
    // --dsw-static-neutral-bluish-950 / 875 / 850 / 800
    static let bg = Color(hex: 0x151517)
    static let layer1 = Color(hex: 0x232324)
    static let layer2 = Color(hex: 0x2C2C2E)
    static let layer3 = Color(hex: 0x38383A)

    // labels
    static let fg = Color(hex: 0xF9FAFB)        // label-primary  (50)
    static let fgSoft = Color(hex: 0xCFD3D6)    // label-secondary (300)
    static let dim = Color(hex: 0xADB2B8)       // label-tertiary (400)
    static let dim2 = Color(hex: 0x81858C)      // (600)

    // borders
    static let line = Color.white.opacity(0.06)
    static let lineStrong = Color.white.opacity(0.12)
    static let lineEmphasis = Color.white.opacity(0.16)

    // accent + status
    static let accent = Color(hex: 0x3B82F6)
    static let ok = Color(hex: 0x4ED17E)
    static let warn = Color(hex: 0xF5A623)
    static let err = Color(hex: 0xF25A5A)

    // surfaces
    static let bubble = Color(hex: 0x2C2C2E)    // --dsw-specific-bubble (dark)
    static let codeBg = Color(hex: 0x101012)
    static let primary = Color(hex: 0xF9FAFB)   // primary button fill (dark)
    static let primaryText = Color(hex: 0x151517)
}

// MARK: - Background

struct ScreenBackground: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()
    }
}

// MARK: - Small building blocks

struct StatusDot: View {
    enum Kind { case idle, online, busy, offline }
    let kind: Kind

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .animation(.easeInOut(duration: 0.25), value: kind)
    }

    private var color: Color {
        switch kind {
        case .idle: return Theme.dim2
        case .online: return Theme.ok
        case .busy: return Theme.accent
        case .offline: return Theme.err
        }
    }
}

struct Shimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: 30, height: 7)
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.25), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 30)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

struct Caret: View {
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Theme.fg)
            .frame(width: 7, height: 17)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func done() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
