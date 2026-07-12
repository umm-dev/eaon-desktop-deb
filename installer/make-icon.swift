import AppKit

// Renders the app's actual brand mark (the same geometry as `AquaMark` /
// `AquaGlyph` in SidebarView.swift — rounded rect at 0.28 corner ratio,
// #F17455 fill, white peak glyph at 0.52 scale with a +0.02 vertical
// offset) into every size a macOS .icns needs, then a build step runs
// `iconutil` on the result. Kept in the repo so the icon can always be
// regenerated from the same source of truth instead of becoming a stray
// binary nobody can reproduce.
//
// Usage: swift installer/make-icon.swift <output-iconset-dir>

let accent = NSColor(calibratedRed: 0xF1 / 255.0, green: 0x74 / 255.0, blue: 0x55 / 255.0, alpha: 1)

func glyphPath(in rect: CGRect) -> CGPath {
    let w = rect.width, h = rect.height, ox = rect.minX, oy = rect.minY
    let path = CGMutablePath()
    path.move(to: CGPoint(x: ox + w * 0.5, y: oy + h * 0.12))
    path.addLine(to: CGPoint(x: ox + w * 0.86, y: oy + h * 0.80))
    path.addCurve(
        to: CGPoint(x: ox + w * 0.14, y: oy + h * 0.80),
        control1: CGPoint(x: ox + w * 0.68, y: oy + h * 0.62),
        control2: CGPoint(x: ox + w * 0.32, y: oy + h * 0.62)
    )
    path.closeSubpath()
    return path
}

func renderIcon(pixels: Int, to url: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not create bitmap rep at \(pixels)px") }
    rep.size = NSSize(width: pixels, height: pixels)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no graphics context") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    // Flip to top-down so the SwiftUI-derived geometry maps 1:1.
    cg.translateBy(x: 0, y: CGFloat(pixels))
    cg.scaleBy(x: 1, y: -1)

    let canvas = CGFloat(pixels)
    // Standard macOS icon margin — the tile doesn't fill the full canvas.
    let margin = canvas * 0.10
    let tile = CGRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)

    let radius = tile.width * 0.28
    cg.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.setFillColor(accent.cgColor)
    cg.fillPath()

    let glyphSize = tile.width * 0.52
    let glyphRect = CGRect(
        x: tile.midX - glyphSize / 2,
        y: tile.midY - glyphSize / 2 + tile.width * 0.02,
        width: glyphSize,
        height: glyphSize
    )
    cg.addPath(glyphPath(in: glyphRect))
    cg.setFillColor(NSColor.white.cgColor)
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
    do { try png.write(to: url) } catch { fatalError("write failed: \(error)") }
}

guard CommandLine.arguments.count == 2 else {
    print("usage: swift make-icon.swift <output-iconset-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// (filename, pixel size) pairs iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in variants {
    renderIcon(pixels: pixels, to: outDir.appendingPathComponent(name))
}
print("rendered \(variants.count) icon sizes into \(outDir.path)")
