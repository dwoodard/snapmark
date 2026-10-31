import AppKit

final class CanvasView: NSView, NSTextFieldDelegate {
    private let renderer: Renderer
    private(set) var items: [Annotation] = []
    private var draft: Annotation?
    private var colors: [Tool: NSColor] = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, $0.defaultColor) })
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero

    var tool: Tool = .arrow
    var onItemsChanged: (() -> Void)?
    var onToolKey: ((Tool) -> Void)?
    var onCommand: ((EditorController.Command) -> Void)?

    init(renderer: Renderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    var canUndo: Bool { !items.isEmpty }
    func color(for tool: Tool) -> NSColor { colors[tool] ?? tool.defaultColor }
    func setColor(_ c: NSColor, for tool: Tool) { colors[tool] = c }

    func undo() {
        commitText()
        guard !items.isEmpty else { return }
        items.removeLast()
        changed()
    }

    private var viewScale: CGFloat { bounds.width / CGFloat(renderer.image.width) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / viewScale, y: p.y / viewScale)
    }

    private func changed() {
        needsDisplay = true
        onItemsChanged?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: viewScale, y: viewScale)
        renderer.draw(items + (draft.map { [$0] } ?? []), in: ctx)
        ctx.restoreGState()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitText()
        let p = imagePoint(event)
        if tool == .text {
            beginText(at: p)
        } else {
            draft = Annotation(tool: tool, start: p, end: p, color: color(for: tool))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard draft != nil else { return }
        var p = imagePoint(event)
        if event.modifierFlags.contains(.shift), let d = draft { p = constrain(from: d.start, to: p, tool: d.tool) }
        draft?.end = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let d = draft else { return }
        draft = nil
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
        let field = NSTextField(frame: CGRect(x: p.x * viewScale, y: p.y * viewScale, width: 240, height: size + 8))
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
            return
        }
        super.keyDown(with: event)
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
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
