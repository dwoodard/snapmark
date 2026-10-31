import AppKit

final class CanvasView: NSView, NSTextFieldDelegate {
    private let renderer: Renderer
    private(set) var items: [Annotation] = []
    private var draft: Annotation?
    private var colors: [Tool: NSColor] = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, $0.defaultColor) })
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero

    private enum DragMode {
        case draw
        case move(CGRect)
        case resize(Int, Int, CGRect)   // x edge (-1 min, 1 max), y edge, starting rect
    }
    private var mode: DragMode = .draw
    private var dragOrigin: CGPoint = .zero

    var tool: Tool = .arrow
    var onItemsChanged: (() -> Void)?
    var onVisibleRectChanged: ((CGRect) -> Void)?
    private var lastVisible: CGRect = .null
    var onToolKey: ((Tool) -> Void)?
    var onCommand: ((EditorController.Command) -> Void)?

    init(renderer: Renderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true   // since macOS 14 views do not clip by default; a zoomed crop would draw over the toolbar
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { cursor(at: imagePoint(event)).set() }
    override func mouseEntered(with event: NSEvent) { cursor(at: imagePoint(event)).set() }

    func load(_ stored: [Annotation]) {
        items = stored
        changed()
    }

    var canUndo: Bool { !items.isEmpty }
    func color(for tool: Tool) -> NSColor { colors[tool] ?? tool.defaultColor }
    func setColor(_ c: NSColor, for tool: Tool) { colors[tool] = c }

    func undo() {
        commitText()
        guard !items.isEmpty else { return }
        items.removeLast()
        changed()
    }

    /// The part of the image on screen: everything, or the last applied (double-clicked) crop.
    var shownRect: CGRect {
        if let a = items.last(where: { $0.tool == .crop && $0.applied }), let r = renderer.effectiveCrop([a]) { return r }
        return CGRect(x: 0, y: 0, width: CGFloat(renderer.image.width), height: CGFloat(renderer.image.height))
    }

    private var viewScale: CGFloat { bounds.width / shownRect.width }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let v = shownRect
        let s = viewScale
        return CGPoint(x: min(max(p.x / s + v.minX, v.minX), v.maxX), y: min(max(p.y / s + v.minY, v.minY), v.maxY))
    }

    private func changed() {
        needsDisplay = true
        onItemsChanged?()
        let v = shownRect
        if v != lastVisible {
            lastVisible = v
            onVisibleRectChanged?(v)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: bounds)
        ctx.interpolationQuality = .high
        let v = shownRect
        ctx.scaleBy(x: viewScale, y: viewScale)
        ctx.translateBy(x: -v.minX, y: -v.minY)
        let all = items + (draft.map { [$0] } ?? [])
        renderer.draw(all, in: ctx)
        ctx.restoreGState()
        if tool == .crop, let crop = renderer.effectiveCrop(all) { drawHandles(for: crop, in: ctx) }
    }

    private func drawHandles(for crop: CGRect, in ctx: CGContext) {
        let v = shownRect, s = viewScale
        let r = CGRect(x: (crop.minX - v.minX) * s, y: (crop.minY - v.minY) * s, width: crop.width * s, height: crop.height * s)
        let size: CGFloat = 9
        for xe in [-1, 0, 1] {
            for ye in [-1, 0, 1] where !(xe == 0 && ye == 0) {
                let cx = xe == -1 ? r.minX : xe == 1 ? r.maxX : r.midX
                let cy = ye == -1 ? r.minY : ye == 1 ? r.maxY : r.midY
                let h = CGRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(h)
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(h)
            }
        }
    }

    // MARK: Mouse

    /// Hit test for the current crop: a handle to resize, the inside to move, or nil to draw a new one.
    private func cropHit(_ p: CGPoint, _ c: CGRect) -> DragMode? {
        let tol = 9 / viewScale
        guard c.insetBy(dx: -tol, dy: -tol).contains(p) else { return nil }
        let xe = abs(p.x - c.minX) < tol ? -1 : abs(p.x - c.maxX) < tol ? 1 : 0
        let ye = abs(p.y - c.minY) < tol ? -1 : abs(p.y - c.maxY) < tol ? 1 : 0
        if xe != 0 || ye != 0 { return .resize(xe, ye, c) }
        return .move(c)
    }

    private func cursor(at p: CGPoint) -> NSCursor {
        guard tool == .crop, let c = renderer.effectiveCrop(items), let hit = cropHit(p, c) else { return .crosshair }
        switch hit {
        case .move: return .openHand
        case .resize(let xe, let ye, _): return xe != 0 && ye != 0 ? .crosshair : (xe != 0 ? .resizeLeftRight : .resizeUpDown)
        case .draw: return .crosshair
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitText()
        let p = imagePoint(event)
        mode = .draw
        if event.clickCount == 2, tool == .crop, let c = renderer.effectiveCrop(items), c.contains(p) {
            // Double-click inside the crop: shrink the view to it.
            draft = nil
            items.append(Annotation(tool: .crop, start: c.origin, end: CGPoint(x: c.maxX, y: c.maxY), color: .white, applied: true))
            changed()
            return
        }
        if tool == .text {
            beginText(at: p)
            return
        }
        if tool == .crop, let c = renderer.effectiveCrop(items), let hit = cropHit(p, c) {
            mode = hit
            dragOrigin = p
            draft = Annotation(tool: .crop, start: c.origin, end: CGPoint(x: c.maxX, y: c.maxY), color: .white)
            return
        }
        draft = Annotation(tool: tool, start: p, end: p, color: color(for: tool))
    }

    override func mouseDragged(with event: NSEvent) {
        guard draft != nil else { return }
        let raw = imagePoint(event)
        let bounds = shownRect
        switch mode {
        case .draw:
            var p = raw
            if event.modifierFlags.contains(.shift), let d = draft { p = constrain(from: d.start, to: p, tool: d.tool) }
            draft?.end = p
        case .move(let r0):
            var r = r0.offsetBy(dx: raw.x - dragOrigin.x, dy: raw.y - dragOrigin.y)
            r.origin.x = min(max(r.origin.x, bounds.minX), bounds.maxX - r.width)
            r.origin.y = min(max(r.origin.y, bounds.minY), bounds.maxY - r.height)
            setCrop(r)
        case .resize(let xe, let ye, let r0):
            let minSize: CGFloat = 16
            let p = CGPoint(x: min(max(raw.x, bounds.minX), bounds.maxX), y: min(max(raw.y, bounds.minY), bounds.maxY))
            var minX = r0.minX, maxX = r0.maxX, minY = r0.minY, maxY = r0.maxY
            if xe == -1 { minX = min(p.x, maxX - minSize) }
            if xe == 1 { maxX = max(p.x, minX + minSize) }
            if ye == -1 { minY = min(p.y, maxY - minSize) }
            if ye == 1 { maxY = max(p.y, minY + minSize) }
            setCrop(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }
        needsDisplay = true
    }

    private func setCrop(_ r: CGRect) {
        draft?.start = r.origin
        draft?.end = CGPoint(x: r.maxX, y: r.maxY)
    }

    override func mouseUp(with event: NSEvent) {
        guard let d = draft else { return }
        draft = nil
        defer { mode = .draw }
        if case .draw = mode {} else if d.rect == renderer.effectiveCrop(items) {
            needsDisplay = true   // a click on a handle without moving
            return
        }
        if hypot(d.end.x - d.start.x, d.end.y - d.start.y) > 4 {
            items.append(d)
            changed()
        } else {
            needsDisplay = true
        }
    }

    /// Shift: arrows snap to 45 degree steps, boxes become squares.
    private func constrain(from s: CGPoint, to p: CGPoint, tool: Tool) -> CGPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        if tool == .arrow {
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let len = hypot(dx, dy)
            return CGPoint(x: s.x + cos(angle) * len, y: s.y + sin(angle) * len)
        }
        let m = max(abs(dx), abs(dy))
        return CGPoint(x: s.x + (dx < 0 ? -m : m), y: s.y + (dy < 0 ? -m : m))
    }

    // MARK: Text

    private func beginText(at p: CGPoint) {
        textOrigin = p
        let size = Renderer.fontSize(pixelScale: renderer.pixelScale) * viewScale
        let v = shownRect
        let field = NSTextField(frame: CGRect(x: (p.x - v.minX) * viewScale, y: (p.y - v.minY) * viewScale, width: 240, height: size + 8))
        field.font = .systemFont(ofSize: size, weight: .bold)
        field.textColor = color(for: .text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        field.delegate = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !text.isEmpty else { return }
        items.append(Annotation(tool: .text, start: textOrigin, end: textOrigin, color: color(for: .text), text: text))
        changed()
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCommand?(.close); return }
        if let ch = event.charactersIgnoringModifiers?.lowercased(),
           let t = Tool.allCases.first(where: { $0.shortcut == ch }) {
            onToolKey?(t)
        }
        // Unhandled keys are swallowed: passing them up makes macOS beep.
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard textField == nil, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "z": onCommand?(.undo)
        case "c": onCommand?(.copy)
        case "s": onCommand?(.save)
        case "w": onCommand?(.close)
        case "e": onCommand?(.openExternal)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
