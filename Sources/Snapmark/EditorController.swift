import AppKit

/// Editor window: tool bar on top, annotatable canvas below.
final class EditorController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let canvas: CanvasView
    private let renderer: Renderer
    private let toolPicker = NSSegmentedControl()
    private let colorWell = NSColorWell()
    private let undoButton = NSButton()
    var onClose: ((EditorController) -> Void)?

    init(capture: Capture.Result) {
        renderer = Renderer(image: capture.image, pixelScale: capture.pixelScale)
        canvas = CanvasView(renderer: renderer)

        // Canvas display size: native point size, shrunk to fit the screen.
        let natural = CGSize(width: CGFloat(capture.image.width) / capture.pixelScale,
                             height: CGFloat(capture.image.height) / capture.pixelScale)
        let maxSize = (NSScreen.main?.visibleFrame.size ?? CGSize(width: 1400, height: 900)).applying(CGAffineTransform(scaleX: 0.85, y: 0.8))
        let fit = min(1, maxSize.width / natural.width, (maxSize.height - 44) / natural.height)
        let size = CGSize(width: (natural.width * fit).rounded(), height: (natural.height * fit).rounded())

        let barHeight: CGFloat = 44
        let contentWidth = max(size.width, 520)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: contentWidth, height: size.height + barHeight),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()

        window.title = "Snapmark"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating

        let content = NSView()
        window.contentView = content

        let bar = buildBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)
        content.addSubview(canvas)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: barHeight),
            canvas.topAnchor.constraint(equalTo: bar.bottomAnchor),
            canvas.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            canvas.widthAnchor.constraint(equalToConstant: size.width),
            canvas.heightAnchor.constraint(equalToConstant: size.height),
        ])

        canvas.onItemsChanged = { [weak self] in self?.undoButton.isEnabled = self?.canvas.canUndo ?? false }
        canvas.onToolKey = { [weak self] tool in self?.select(tool) }
        canvas.onCommand = { [weak self] cmd in self?.run(cmd) }
        select(Tool(rawValue: Settings.defaultTool) ?? .arrow)
        undoButton.isEnabled = false
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    enum Command { case copy, save, undo, close }

    private func run(_ cmd: Command) {
        switch cmd {
        case .undo: canvas.undo()
        case .close: window.close()
        case .save:
            if let img = renderer.render(canvas.items), (try? Output.save(img)) != nil { Output.playSound() }
        case .copy:
            if let img = renderer.render(canvas.items) {
                Output.copyToClipboard(img)
                if Settings.editorSaveOnCopy { _ = try? Output.save(img) }
            }
            Output.playSound()
            if Settings.editorCloseAfterCopy { window.close() }
        }
    }

    private func buildBar() -> NSView {
        toolPicker.segmentCount = Tool.allCases.count
        toolPicker.trackingMode = .selectOne
        toolPicker.segmentStyle = .texturedRounded
        for t in Tool.allCases {
            toolPicker.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.label), forSegment: t.rawValue)
            toolPicker.setToolTip(t.label, forSegment: t.rawValue)
            toolPicker.setWidth(36, forSegment: t.rawValue)
        }
        toolPicker.target = self
        toolPicker.action = #selector(toolChanged)

        colorWell.colorWellStyle = .minimal
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.widthAnchor.constraint(equalToConstant: 36).isActive = true

        configure(undoButton, symbol: "arrow.uturn.backward", title: "Undo", action: #selector(undoTapped))
        let save = NSButton(); configure(save, symbol: "square.and.arrow.down", title: "Save", action: #selector(saveTapped))
        let copy = NSButton(); configure(copy, symbol: "doc.on.doc", title: "Copy", action: #selector(copyTapped))
        copy.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [toolPicker, colorWell, undoButton, spacer, save, copy])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        return stack
    }

    private func configure(_ b: NSButton, symbol: String, title: String, action: Selector) {
        b.title = title
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        b.imagePosition = .imageLeading
        b.bezelStyle = .texturedRounded
        b.target = self
        b.action = action
    }

    private func select(_ tool: Tool) {
        canvas.commitText()
        canvas.tool = tool
        toolPicker.selectedSegment = tool.rawValue
        colorWell.color = canvas.color(for: tool)
        colorWell.isEnabled = tool != .blur
    }

    @objc private func toolChanged() { select(Tool(rawValue: toolPicker.selectedSegment) ?? .arrow) }
    @objc private func colorChanged() { canvas.setColor(colorWell.color, for: canvas.tool) }
    @objc private func undoTapped() { run(.undo) }
    @objc private func saveTapped() { run(.save) }
    @objc private func copyTapped() { run(.copy) }

    func windowWillClose(_ notification: Notification) {
        canvas.commitText()
        onClose?(self)
    }
}
