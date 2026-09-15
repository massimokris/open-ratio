import AppKit
import RatioCore

/// A non-template image keeps the active category visible in the system menu bar.
enum MenuIndicator {
    static func image(category: ActivityCategory?, paused: Bool) -> NSImage {
        let color: NSColor
        if paused || category == nil { color = NSColor(srgbRed: 1, green: 0.69, blue: 0, alpha: 1) }
        else if category == .create { color = NSColor(srgbRed: 40 / 255, green: 205 / 255, blue: 65 / 255, alpha: 1) }
        else { color = NSColor(srgbRed: 1, green: 59 / 255, blue: 48 / 255, alpha: 1) }
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            color.setStroke()
            let outline = NSBezierPath(ovalIn: NSRect(x: 0.75, y: 0.75, width: 14.5, height: 14.5))
            outline.lineWidth = 1.4
            outline.stroke()
            let mark = NSBezierPath()
            mark.lineWidth = 1.5
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            if paused {
                mark.move(to: NSPoint(x: 6, y: 5)); mark.line(to: NSPoint(x: 6, y: 11))
                mark.move(to: NSPoint(x: 10, y: 5)); mark.line(to: NSPoint(x: 10, y: 11))
            } else if let category {
                let startY: CGFloat = category == .create ? 5 : 11
                let endY: CGFloat = category == .create ? 11 : 5
                mark.move(to: NSPoint(x: 5, y: startY)); mark.line(to: NSPoint(x: 11, y: endY))
                mark.move(to: NSPoint(x: 6, y: endY)); mark.line(to: NSPoint(x: 11, y: endY)); mark.line(to: NSPoint(x: 11, y: category == .create ? 6 : 10))
            } else {
                mark.move(to: NSPoint(x: 5, y: 8)); mark.line(to: NSPoint(x: 11, y: 8))
            }
            mark.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
