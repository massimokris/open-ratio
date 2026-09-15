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
    static let sidebar = background
    static let line = adaptive(light: 0xDDDDDD, dark: 0x242424)
    static let text = adaptive(light: 0x151515, dark: 0xF5F5F5)
    static let secondary = adaptive(light: 0x737373, dark: 0x808080)
    static let muted = adaptive(light: 0x999999, dark: 0x666666)
    static func font(size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .bold ? "Menlo-Bold" : "Menlo-Regular", fixedSize: size)
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
    }
}

struct RatioMark: View {
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            Circle().strokeBorder(.primary, lineWidth: 1.5)
            Capsule().fill(.primary).frame(width: 1.5, height: size * 0.92).rotationEffect(.degrees(36))
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.8).foregroundStyle(.secondary)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(RatioTheme.line).frame(height: 0.5) }
}

struct SourceIcon: View {
    let source: ActivitySource
    var body: some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .medium))
            .frame(width: 34, height: 34).background(RatioTheme.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
    private var symbol: String {
        if source.kind == .website { return "globe" }
        let name = source.name.lowercased()
        if name.contains("code") || name.contains("terminal") { return "chevron.left.forwardslash.chevron.right" }
        if name.contains("figma") { return "square.on.circle" }
        if name.contains("notes") { return "note.text" }
        if name.contains("spotify") { return "music.note" }
        if name.contains("slack") { return "number" }
        if name.contains("finder") { return "folder" }
        return "app"
    }
}

struct CategoryPicker: View {
    let source: ActivitySource
    let category: ActivityCategory?
    let classify: (ActivityCategory?) -> Void
    var compact = false
    var body: some View {
        Menu {
            Button("Create") { classify(.create) }
            Button("Consume") { classify(.consume) }
            Divider()
            Button("Leave unclassified") { classify(nil) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(RatioTheme.category(category)).frame(width: 5, height: 5)
                Text(category?.title ?? "Unclassified").font(.system(size: compact ? 10 : 11, design: .monospaced))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }.foregroundStyle(RatioTheme.category(category)).padding(.horizontal, 9).padding(.vertical, 6)
                .background(RatioTheme.category(category).opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).foregroundColor(RatioTheme.category(category)).fixedSize()
            .accessibilityLabel("Category for \(source.name): \(category?.title ?? "Unclassified")")
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RatioTheme.line.opacity(configuration.isPressed ? 0.9 : 0.4), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
    }
}
