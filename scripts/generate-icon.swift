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
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "IconRendering", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 218, yRadius: 218)
    color(17, 23, 19).setFill()
    tile.fill()
    color(51, 67, 56).setStroke()
    tile.lineWidth = 4
    tile.stroke()

    func arc(start: CGFloat, end: CGFloat, stroke: NSColor) {
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 298, startAngle: start, endAngle: end, clockwise: true)
        path.lineWidth = 76
        stroke.setStroke()
        path.stroke()
    }
    arc(start: 90, end: -150, stroke: color(163, 235, 125))
    arc(start: -154, end: -266, stroke: color(241, 240, 231))

    let arrows = NSBezierPath()
    arrows.move(to: NSPoint(x: 430, y: 420))
    arrows.line(to: NSPoint(x: 430, y: 612))
    arrows.move(to: NSPoint(x: 367, y: 548))
    arrows.line(to: NSPoint(x: 430, y: 612))
    arrows.line(to: NSPoint(x: 493, y: 548))
    arrows.move(to: NSPoint(x: 594, y: 604))
    arrows.line(to: NSPoint(x: 594, y: 412))
    arrows.move(to: NSPoint(x: 531, y: 476))
    arrows.line(to: NSPoint(x: 594, y: 412))
    arrows.line(to: NSPoint(x: 657, y: 476))
    arrows.lineWidth = 34
    arrows.lineCapStyle = .square
    color(241, 240, 231).setStroke()
    arrows.stroke()
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
