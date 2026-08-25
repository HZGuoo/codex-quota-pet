import AppKit
import SwiftUI

enum AuroraStyle {
    static let accent = Color(red: 0.42, green: 0.35, blue: 0.87)
    static let accentBlue = Color(red: 0.28, green: 0.65, blue: 0.96)
    static let accentPurple = Color(red: 0.65, green: 0.42, blue: 0.94)

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.14, blue: 0.20).opacity(0.72)
            : Color(red: 0.965, green: 0.973, blue: 1.0).opacity(0.72)
    }
}

struct MacGlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

struct AuroraBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var material: NSVisualEffectView.Material

    var body: some View {
        ZStack {
            MacGlassBackground(material: material)
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.13, green: 0.16, blue: 0.25).opacity(0.84),
                        Color(red: 0.17, green: 0.13, blue: 0.24).opacity(0.72)
                    ]
                    : [
                        Color(red: 0.92, green: 0.97, blue: 1.0).opacity(0.82),
                        Color(red: 0.97, green: 0.93, blue: 1.0).opacity(0.68)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [AuroraStyle.accentBlue.opacity(colorScheme == .dark ? 0.11 : 0.16), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 340
            )
            RadialGradient(
                colors: [AuroraStyle.accentPurple.opacity(colorScheme == .dark ? 0.10 : 0.14), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 320
            )
        }
        .allowsHitTesting(false)
    }
}

struct GlassCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 14
    var shadowOpacity: Double = 0.08

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AuroraStyle.surface(for: colorScheme),
                                AuroraStyle.accentBlue.opacity(colorScheme == .dark ? 0.025 : 0.045),
                                AuroraStyle.accentPurple.opacity(colorScheme == .dark ? 0.035 : 0.055)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? AuroraStyle.accentPurple.opacity(0.18)
                            : Color.white.opacity(0.78),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: AuroraStyle.accent.opacity(shadowOpacity * (colorScheme == .dark ? 1.15 : 0.72)),
                radius: 14,
                y: 6
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 14, shadowOpacity: Double = 0.08) -> some View {
        background(
            GlassCardBackground(
                cornerRadius: cornerRadius,
                shadowOpacity: shadowOpacity
            )
        )
    }
}
