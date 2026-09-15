#!/usr/bin/env swift
import AppKit
import CoreText
import Foundation

// Run: swift scripts/generate-dmg-background.swift build/dmg-background.tiff
// Finder draws the real app and Applications icons over this original vector artwork.
let canvasSize = NSSize(width: 580, height: 360)

enum BackgroundError: LocalizedError {
    case usage
    case bitmap
    case encoding

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: swift scripts/generate-dmg-background.swift <output.tiff>"
        case .bitmap:
            return "Could not create the DMG background drawing surface."
        case .encoding:
            return "Could not encode the DMG background as TIFF."
        }
    }
}

func gray(_ component: CGFloat) -> NSColor {
    NSColor(srgbRed: component / 255, green: component / 255,
        blue: component / 255, alpha: 1)
}

func render(scale: Int) throws -> NSBitmapImageRep {
    guard let rawBitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width) * scale,
        pixelsHigh: Int(canvasSize.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let bitmap = rawBitmap.retagging(with: .sRGB),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw BackgroundError.bitmap
    }

    // Both representations have the same logical size; the 2× pixels must not
    // make Finder enlarge the background on a Retina display.
    bitmap.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.shouldAntialias = true

    gray(246).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

    // Match the icon row at y=160 measured down from the Finder content top.
    let arrowY = canvasSize.height - 160
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 246, y: arrowY))
    arrow.line(to: NSPoint(x: 334, y: arrowY))
    arrow.move(to: NSPoint(x: 324, y: arrowY + 10))
    arrow.line(to: NSPoint(x: 334, y: arrowY))
    arrow.line(to: NSPoint(x: 324, y: arrowY - 10))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    gray(112).setStroke()
    arrow.stroke()

    let instruction = "Drag Ratio into your Applications folder"
    let font = NSFont(name: "SFMono-Regular", size: 12.5)
        ?? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    let text = NSAttributedString(string: instruction,
        attributes: [.font: font, .foregroundColor: gray(72)])
    let line = CTLineCreateWithAttributedString(text)
    let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.cgContext.textMatrix = .identity
    context.cgContext.textPosition = CGPoint(
        x: (canvasSize.width - textWidth) / 2,
        y: canvasSize.height - 270)
    CTLineDraw(line, context.cgContext)
    context.flushGraphics()
    return bitmap
}

do {
    guard CommandLine.arguments.count == 2 else { throw BackgroundError.usage }
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    let representations = try [1, 2].map { try render(scale: $0) }
    guard let tiff = NSBitmapImageRep.representationOfImageReps(in: representations,
        using: .tiff, properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue]) else {
        throw BackgroundError.encoding
    }
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try tiff.write(to: output, options: .atomic)
    print(output.path)
} catch {
    FileHandle.standardError.write(Data("DMG background: \(error.localizedDescription)\n".utf8))
    exit(1)
}
