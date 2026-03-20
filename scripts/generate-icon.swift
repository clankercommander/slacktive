import AppKit

func generateIcon(size: Int, scale: Int, outputPath: String) {
    let pixelSize = size * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))

    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)

    // White rounded-rect background
    let bgPath = NSBezierPath(roundedRect: bounds, xRadius: CGFloat(pixelSize) * 0.22, yRadius: CGFloat(pixelSize) * 0.22)
    NSColor.white.setFill()
    bgPath.fill()

    // Green circle in center
    let circleInset = CGFloat(pixelSize) * 0.25
    let circleRect = bounds.insetBy(dx: circleInset, dy: circleInset)
    let circlePath = NSBezierPath(ovalIn: circleRect)
    NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0).setFill()
    circlePath.fill()

    // Subtle inner glow on the circle
    let glowInset = CGFloat(pixelSize) * 0.32
    let glowRect = bounds.insetBy(dx: glowInset, dy: glowInset)
    let glowPath = NSBezierPath(ovalIn: glowRect)
    NSColor(white: 1.0, alpha: 0.25).setFill()
    glowPath.fill()

    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(outputPath)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated: \(outputPath) (\(pixelSize)x\(pixelSize))")
    } catch {
        print("Failed to write \(outputPath): \(error.localizedDescription)")
    }
}

// Derive the asset path relative to this script's location
// Script is at: <project>/scripts/generate-icon.swift
// Target is at: <project>/Slacktive/Assets.xcassets/AppIcon.appiconset/
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let basePath = projectDir.appendingPathComponent("Slacktive/Assets.xcassets/AppIcon.appiconset").path

let configs: [(size: Int, scale: Int, filename: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

for config in configs {
    generateIcon(size: config.size, scale: config.scale, outputPath: "\(basePath)/\(config.filename)")
}
