import SwiftUI
import RatioCore

/// Reference colors in sRGB, with the same compact geometry in light appearance.
enum RatioTheme {
    static let create = adaptive(light: 0x16852C, dark: 0x28CD41)
    static let consume = adaptive(light: 0xD72C22, dark: 0xFF3B30)
    static let unknown = adaptive(light: 0xA06500, dark: 0xFFB000)
    static let background = adaptive(light: 0xFAFAFA, dark: 0x0F0F0F)
    static let panel = adaptive(light: 0xEEEEEE, dark: 0x1A1A1A)
    static let selected = adaptive(light: 0xF3F3F3, dark: 0x131313)
    static let line = adaptive(light: 0xDDDDDD, dark: 0x242424)
    static let text = adaptive(light: 0x151515, dark: 0xF5F5F5)
    static let secondary = adaptive(light: 0x737373, dark: 0x808080)
    static let muted = adaptive(light: 0x999999, dark: 0x666666)
    static func font(size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        Font(RatioTypography.nativeFont(size: size, weight: weight == .bold ? .bold : .regular))
    }
    static func lineSpacing(size: CGFloat = 12) -> CGFloat {
        let font = RatioTypography.nativeFont(size: size)
        return max(0, RatioTypography.lineHeight(size: size) - NSLayoutManager().defaultLineHeight(for: font))
    }
    static func category(_ category: ActivityCategory?) -> Color {
        switch category { case .create: return create; case .consume: return consume; case nil: return unknown }
    }
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RatioTheme.line : Color.clear)
            .pointingHandCursor()
    }
}

struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterButtonSurface(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct FooterButtonSurface<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var highlighted: Bool { isEnabled && (isHovered || isPressed) }

    var body: some View {
        label
            .foregroundStyle(highlighted ? Color.black : RatioTheme.text)
            .background(highlighted ? Color.white : Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onChange(of: isEnabled) { if !$0 { isHovered = false } }
            .onDisappear { isHovered = false }
            .pointingHandCursor()
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(RatioTheme.font(size: 10))
            .foregroundStyle(.secondary)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(RatioTheme.line).frame(height: 0.5) }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(RatioTheme.font())
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RatioTheme.line.opacity(configuration.isPressed ? 0.9 : 0.4),
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .pointingHandCursor()
    }
}
