#!/usr/bin/env swift
import AppKit

// Draws Aikon's mark — the same rounded square + diamond as `BrandMark` and
// `AppIcon` — at every size `.iconset` needs, then hands the folder to
// `iconutil` to produce `Resources/AppIcon.icns`.
//
// Run from the repo root:
//   swift scripts/make-icon.swift

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // scripts
    .deletingLastPathComponent() // repo root
let resourcesDir = repoRoot.appendingPathComponent("Resources")
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")

func draw(pixelSize: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)

    // ~22% corner radius, matching AppIcon.swift and the Dock's own rounding.
    let cornerRadius = rect.width * 0.22
    let background = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor(srgbRed: 0xFF / 255.0, green: 0x8A / 255.0, blue: 0x4C / 255.0, alpha: 1).setFill()
    background.fill()

    // Same proportion as AppIcon.swift's Dock mark: a 24pt diamond on a 56pt
    // square, ~43% of the side.
    let markSize = rect.width * (24.0 / 56.0)
    let markRect = CGRect(x: rect.midX - markSize / 2, y: rect.midY - markSize / 2,
                           width: markSize, height: markSize)
    let diamond = NSBezierPath()
    diamond.move(to: CGPoint(x: markRect.midX, y: markRect.minY))
    diamond.line(to: CGPoint(x: markRect.maxX, y: markRect.midY))
    diamond.line(to: CGPoint(x: markRect.midX, y: markRect.maxY))
    diamond.line(to: CGPoint(x: markRect.minX, y: markRect.midY))
    diamond.close()
    NSColor.white.setFill()
    diamond.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not encode \(url.lastPathComponent)"])
    }
    try data.write(to: url)
}

// name -> base point size; each also gets an @2x file at double the pixels.
let sizes: [(name: String, points: Int)] = [
    ("16x16", 16),
    ("32x32", 32),
    ("64x64", 64),
    ("128x128", 128),
    ("256x256", 256),
    ("512x512", 512),
]

do {
    try? FileManager.default.removeItem(at: iconsetDir)
    try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

    for size in sizes {
        let rep1x = draw(pixelSize: size.points)
        try writePNG(rep1x, to: iconsetDir.appendingPathComponent("icon_\(size.name).png"))

        let rep2x = draw(pixelSize: size.points * 2)
        try writePNG(rep2x, to: iconsetDir.appendingPathComponent("icon_\(size.name)@2x.png"))
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        throw NSError(domain: "make-icon", code: Int(task.terminationStatus),
                       userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }

    try? FileManager.default.removeItem(at: iconsetDir)
    print("wrote \(icnsPath.path)")
} catch {
    FileHandle.standardError.write("make-icon failed: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
