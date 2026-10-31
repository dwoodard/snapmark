// Draws the Snapmark app icon (the logo on a dark tile) and writes AppIcon.icns plus a 1024 px preview.
// Needs source/logo-subject.png next to it.
//   swiftc -O packaging/icon/make-icon.swift -o /tmp/make-icon && /tmp/make-icon packaging/icon
// The outputs are committed, so building the app never needs to run this.
import AppKit

func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let outDirArg = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let logoImage: CGImage? = {
    guard let ns = NSImage(contentsOf: outDirArg.appendingPathComponent("source/logo-subject.png")) else { return nil }
    return ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
}()

/// Draws on a 1024 x 1024 canvas, scaled to `px`. Origin bottom-left.
func render(px: Int) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // macOS icon grid: an 824 pt tile centered in the canvas, leaving room for the shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.35))
    ctx.addPath(tile)
    ctx.setFillColor(color(0x15151B))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let blue = CGGradient(colorsSpace: cs, colors: [color(0x2C2C36), color(0x0B0B10)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(blue, start: CGPoint(x: 280, y: 924), end: CGPoint(x: 744, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let sheen = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 520), options: [.drawsBeforeStartLocation])
    ctx.restoreGState()

    ctx.addPath(tile)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // The logo, centered on the tile. It has its own red glow, so it sits on the dark tile without a frame.
    if let logo = logoImage {
        let side: CGFloat = 700
        ctx.interpolationQuality = .high
        ctx.draw(logo, in: CGRect(x: 512 - side / 2, y: 512 - side / 2 - 8, width: side, height: side))
    }

    return ctx.makeImage()!
}

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let outDir = outDirArg
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Each size is drawn at its own resolution, not scaled down, so small icons stay crisp.
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                              ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    try png(render(px: px)).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try png(render(px: 1024)).write(to: outDir.appendingPathComponent("icon-1024.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", "-o", outDir.appendingPathComponent("AppIcon.icns").path, iconset.path]
try p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "Wrote AppIcon.icns and icon-1024.png" : "iconutil failed")
