import AppKit
import SwiftUI

struct AppActionButtonStyle: ButtonStyle {
    var foregroundColor: Color = .primary

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? AuroraStyle.accent.opacity(0.14)
                            : AuroraStyle.surface(for: colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        AuroraStyle.accent.opacity(configuration.isPressed ? 0.32 : 0.15),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.38)
    }
}
