import AppKit
import CoreImage

enum Tool: Int, CaseIterable {
    case arrow, rect, highlight, text, blur, crop

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .highlight: "highlighter"
        case .text: "textformat"
        case .blur: "eye.slash"
        case .crop: "crop"
        }
    }
    var label: String {
        switch self {
        case .arrow: "Arrow (A)"
        case .rect: "Rectangle (R)"
        case .highlight: "Highlight (H)"
        case .text: "Text (T)"
        case .blur: "Blur (B)"
        case .crop: "Crop (C)"
        }
    }
    var shortcut: String {
        switch self {
        case .arrow: "a"
        case .rect: "r"
        case .highlight: "h"
        case .text: "t"
        case .blur: "b"
        case .crop: "c"
        }
    }
    var defaultColor: NSColor {
        self == .highlight ? NSColor(srgbRed: 1, green: 0.85, blue: 0, alpha: 1) : NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1)
    }
}

/// Coordinates are image pixels, origin top-left.
struct Annotation {
    var tool: Tool
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var text = ""
    /// Crop only: the editor shows just this region (double-click).
    var applied = false

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
    }
}

/// Draws the base image plus annotations. Used for both the live canvas and the exported image.
final class Renderer {
    let image: CGImage
    let pixelScale: CGFloat
    private lazy var blurred: CGImage = makeBlurred()

    init(image: CGImage, pixelScale: CGFloat) {
        self.image = image
        self.pixelScale = pixelScale
    }

    private var width: CGFloat { CGFloat(image.width) }
    private var height: CGFloat { CGFloat(image.height) }

    private func makeBlurred() -> CGImage {
        let ci = CIImage(cgImage: image)
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: CGFloat(Settings.blurStrength) * pixelScale).cropped(to: ci.extent)
        return CIContext().createCGImage(out, from: ci.extent) ?? image
    }

    private func drawBase(_ img: CGImage, in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.restoreGState()
    }

    /// The crop in effect: the last crop annotation, clamped to the image. Nil when there is none.
    func effectiveCrop(_ items: [Annotation]) -> CGRect? {
        guard let c = items.last(where: { $0.tool == .crop })?.rect else { return nil }
        let r = c.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        return r.width >= 8 && r.height >= 8 ? r : nil
    }

    /// `ctx` must be flipped (origin top-left) and sized in image pixels.
    /// `previewCrop` dims everything outside the crop; export passes false.
    func draw(_ items: [Annotation], in ctx: CGContext, previewCrop: Bool = true) {
        drawBase(image, in: ctx)
        let line = CGFloat(Settings.lineWidth) * pixelScale
        for a in items {
            ctx.saveGState()
            switch a.tool {
            case .arrow: drawArrow(a, line: line, in: ctx)
            case .rect:
                ctx.setStrokeColor(a.color.cgColor)
                ctx.setLineWidth(line)
                ctx.stroke(a.rect)
            case .highlight:
                ctx.setFillColor(a.color.withAlphaComponent(0.4).cgColor)
                ctx.fill(a.rect)
            case .blur:
                ctx.clip(to: a.rect)
                drawBase(blurred, in: ctx)
            case .text:
                drawText(a, in: ctx)
            case .crop:
                break   // applied below and at export
            }
            ctx.restoreGState()
        }
        if previewCrop, let crop = effectiveCrop(items) {
            ctx.saveGState()
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.addRect(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.addRect(crop)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(pixelScale)
            ctx.stroke(crop)
            ctx.restoreGState()
        }
    }

    private func drawArrow(_ a: Annotation, line: CGFloat, in ctx: CGContext) {
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let ux = dx / len, uy = dy / len
        let head = min(len * 0.6, 16 * pixelScale + line * 2)
        let base = CGPoint(x: a.end.x - ux * head * 0.8, y: a.end.y - uy * head * 0.8)

        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(line)
        ctx.setLineCap(.round)
        ctx.move(to: a.start)
        ctx.addLine(to: base)
        ctx.strokePath()

        let nx = -uy, ny = ux
        let half = head * 0.5
        ctx.move(to: a.end)
        ctx.addLine(to: CGPoint(x: a.end.x - ux * head + nx * half, y: a.end.y - uy * head + ny * half))
        ctx.addLine(to: CGPoint(x: a.end.x - ux * head - nx * half, y: a.end.y - uy * head - ny * half))
        ctx.closePath()
        ctx.fillPath()
    }

    private func drawText(_ a: Annotation, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Renderer.fontSize(pixelScale: pixelScale), weight: .bold),
            .foregroundColor: a.color,
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (a.text as NSString).draw(at: a.start, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    static func fontSize(pixelScale: CGFloat) -> CGFloat { CGFloat(Settings.textSize) * pixelScale }

    func render(_ items: [Annotation]) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let crop = effectiveCrop(items) ?? CGRect(x: 0, y: 0, width: width, height: height)
        guard let ctx = CGContext(data: nil, width: Int(crop.width), height: Int(crop.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: crop.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -crop.minX, y: -crop.minY)
        draw(items, in: ctx, previewCrop: false)
        return ctx.makeImage()
    }
}
