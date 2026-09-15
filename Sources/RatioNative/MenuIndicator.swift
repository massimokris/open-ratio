import AppKit
import RatioCore

/// Status text and the pause image share the active category's native color.
enum MenuIndicator {
    static func color(category: ActivityCategory?, paused: Bool) -> NSColor {
        if paused || category == nil { return .white }
        if category == .create { return NSColor(srgbRed: 40 / 255, green: 205 / 255, blue: 65 / 255, alpha: 1) }
        return NSColor(srgbRed: 1, green: 59 / 255, blue: 48 / 255, alpha: 1)
    }

    static func glyph(category: ActivityCategory?) -> String {
        switch category {
        case .create: return "↑"
        case .consume: return "↓"
        case nil: return "?"
        }
    }

    static func image(category: ActivityCategory?, paused: Bool) -> NSImage {
        let color = Self.color(category: category, paused: paused)
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            if paused {
                color.setStroke()
                let mark = NSBezierPath()
                mark.lineWidth = 1.5
                mark.lineCapStyle = .round
                mark.move(to: NSPoint(x: 6, y: 5)); mark.line(to: NSPoint(x: 6, y: 11))
                mark.move(to: NSPoint(x: 10, y: 5)); mark.line(to: NSPoint(x: 10, y: 11))
                mark.stroke()
            } else {
                let text = NSAttributedString(string: glyph(category: category), attributes: [
                    .font: RatioTypography.glyphFont(), .foregroundColor: color
                ])
                let size = text.size()
                text.draw(at: NSPoint(x: (16 - size.width) / 2, y: (16 - size.height) / 2))
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
