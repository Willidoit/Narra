import SwiftUI

// Shared pill-style button used across the onboarding wizard and Settings
// model rows. Two visual modes — `.filled` (ink fill, canvas text) for the
// primary action, `.outline` (white-12% stroke on transparent fill) for
// secondary actions. Disabled state dims to 40% opacity.

struct PillButton: View {
    enum Style { case filled, outline }

    let title: String
    let systemImage: String?
    let style: Style
    let isDisabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        style: Style = .filled,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(Typography.sans(12, .medium))
            }
            .foregroundStyle(style == .filled ? Palette.canvas : Palette.ink)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(style == .filled ? Palette.ink : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(
                        style == .filled ? Color.clear : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .opacity(isDisabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
