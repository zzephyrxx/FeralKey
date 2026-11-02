// SPDX-License-Identifier: GPL-3.0-or-later
// Package the user-provided logo as a macOS icon, preserving its artwork.
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
      source.size.width > 0, source.size.height > 0 else {
    fputs("Usage: MakeIcon.swift <logo.png> <output.iconset>\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "FeralKeyIcon", code: 1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.imageInterpolation = .high
        let factor = min(CGFloat(pixels)/source.size.width, CGFloat(pixels)/source.size.height)
        let width = source.size.width*factor, height = source.size.height*factor
        source.draw(in: NSRect(x: (CGFloat(pixels)-width)/2, y: (CGFloat(pixels)-height)/2, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "FeralKeyIcon", code: 2) }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: output.appendingPathComponent(name))
    }
}
