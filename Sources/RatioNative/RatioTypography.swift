import AppKit

/// Native equivalent of the reference's SF Mono stack and 1.5 line height.
enum RatioTypography {
    static let letterSpacing: CGFloat = 0.5

    static func nativeFont(size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSFont {
        if let font = NSFont(name: "SFMono-Regular", size: size) ?? NSFont(name: "SF Mono", size: size) {
            let descriptor = font.fontDescriptor.addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
            ])
            return NSFont(descriptor: descriptor, size: size) ?? font
        }
        // macOS exposes its bundled SF Mono through this API even when the
        // public family name is unavailable. Keep its natural letter spacing.
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func lineHeight(size: CGFloat = 12) -> CGFloat { size * 1.5 }
}
