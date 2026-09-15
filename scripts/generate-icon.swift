#!/usr/bin/env swift
import AppKit
import Foundation

// Original vector artwork, rendered at every standard macOS icon resolution.
// Run: swift scripts/generate-icon.swift build/RatioNative.iconset
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/RatioNative.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func render(pixels: Int, filename: String) throws {
    // Tag the drawing surface explicitly so the exported pixels use sRGB.
    guard let rawBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let bitmap = rawBitmap.retagging(with: .sRGB),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "IconRendering", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 218, yRadius: 218)
    NSColor.black.setFill()
    tile.fill()

    let createColor = color(40, 205, 65)
    let consumeColor = color(255, 59, 48)
    let compositionScale: CGFloat = 1.6
    let strokeWidth: CGFloat = 34 * compositionScale
    var arrowTransform = AffineTransform.identity
    arrowTransform.translate(x: 512, y: 578)
    arrowTransform.scale(compositionScale)
    arrowTransform.translate(x: -512, y: -512)

    func strokeArrow(_ path: NSBezierPath, color: NSColor) {
        // Keep the original arrow paths and square caps, scaling them together.
        path.transform(using: arrowTransform)
        path.lineWidth = strokeWidth
        path.lineCapStyle = .square
        color.setStroke()
        path.stroke()
    }
    let upArrow = NSBezierPath()
    upArrow.move(to: NSPoint(x: 430, y: 420))
    upArrow.line(to: NSPoint(x: 430, y: 612))
    upArrow.move(to: NSPoint(x: 367, y: 548))
    upArrow.line(to: NSPoint(x: 430, y: 612))
    upArrow.line(to: NSPoint(x: 493, y: 548))
    strokeArrow(upArrow, color: createColor)

    let downArrow = NSBezierPath()
    downArrow.move(to: NSPoint(x: 594, y: 604))
    downArrow.line(to: NSPoint(x: 594, y: 412))
    downArrow.move(to: NSPoint(x: 531, y: 476))
    downArrow.line(to: NSPoint(x: 594, y: 412))
    downArrow.line(to: NSPoint(x: 657, y: 476))
    strokeArrow(downArrow, color: consumeColor)

    let ratioLine = NSRect(x: 174, y: 232 - strokeWidth / 2, width: 676, height: strokeWidth)
    let createWidth = ratioLine.width * 0.68
    // Filled rectangles keep the split exactly 68/32, without overlapping caps.
    createColor.setFill()
    NSBezierPath(rect: NSRect(x: ratioLine.minX, y: ratioLine.minY,
        width: createWidth, height: strokeWidth)).fill()
    consumeColor.setFill()
    NSBezierPath(rect: NSRect(x: ratioLine.minX + createWidth, y: ratioLine.minY,
        width: ratioLine.width - createWidth, height: strokeWidth)).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconRendering", code: 2)
    }
    try png.write(to: output.appendingPathComponent(filename), options: .atomic)
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size, filename: "icon_\(size)x\(size).png")
    try render(pixels: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
print(output.path)
