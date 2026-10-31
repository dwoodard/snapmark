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
    let historyID: String?
    private let barHeight: CGFloat = 44
    private var lastSavedURL: URL?
    private var canvasWidth: NSLayoutConstraint!
    private var canvasHeight: NSLayoutConstraint!

    /// Natural point size shrunk to fit the screen.
    private static func fit(_ natural: CGSize) -> CGSize {
        let maxSize = (NSScreen.main?.visibleFrame.size ?? CGSize(width: 1400, height: 900)).applying(CGAffineTransform(scaleX: 0.85, y: 0.8))
        let f = min(1, maxSize.width / natural.width, (maxSize.height - 44) / natural.height)
        return CGSize(width: (natural.width * f).rounded(), height: (natural.height * f).rounded())
    }

    /// Resize the window to the visible region (full image, or a double-clicked crop).
    private func relayout(for visible: CGRect) {
        let size = EditorController.fit(CGSize(width: visible.width / renderer.pixelScale, height: visible.height / renderer.pixelScale))
        canvasWidth.constant = size.width
        canvasHeight.constant = size.height
        let old = window.frame
        // Content size, not frame size: the title bar sits on top of it. Keep the toolbar visible for tiny crops.
        let content = NSRect(x: 0, y: 0, width: max(size.width, 800), height: max(size.height, 120) + barHeight)
        var frame = window.frameRect(forContentRect: content)
        frame.origin = NSPoint(x: old.minX, y: old.maxY - frame.height)
        window.setFrame(frame, display: true, animate: true)
        canvas.needsDisplay = true
    }

    init(capture: Capture.Result, historyID: String?, annotations: [Annotation] = []) {
        self.historyID = historyID
        renderer = Renderer(image: capture.image, pixelScale: capture.pixelScale)
        canvas = CanvasView(renderer: renderer)

        let size = EditorController.fit(CGSize(width: CGFloat(capture.image.width) / capture.pixelScale,
                                               height: CGFloat(capture.image.height) / capture.pixelScale))

        let contentWidth = max(size.width, 800)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: contentWidth, height: size.height + barHeight),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()

        window.title = "Snapmark"
        window.isReleasedWhenClosed = false
        window.delegate = self

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
        ])
        canvasWidth = canvas.widthAnchor.constraint(equalToConstant: size.width)
        canvasHeight = canvas.heightAnchor.constraint(equalToConstant: size.height)
        NSLayoutConstraint.activate([canvasWidth, canvasHeight])

        canvas.onItemsChanged = { [weak self] in self?.undoButton.isEnabled = self?.canvas.canUndo ?? false }
        canvas.onVisibleRectChanged = { [weak self] rect in self?.relayout(for: rect) }
        canvas.onToolKey = { [weak self] tool in self?.select(tool) }
        canvas.onCommand = { [weak self] cmd in self?.run(cmd) }
        select(Tool(rawValue: Settings.defaultTool) ?? .arrow)
        canvas.load(annotations)
        relayout(for: canvas.shownRect)
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    enum Command { case copy, save, undo, close, openExternal, openFolder, delete }

    private func run(_ cmd: Command) {
        switch cmd {
        case .undo: canvas.undo()
        case .openExternal: openInExternalEditor()
        case .delete:
            // Discard: drop it from Recent Screenshots, trash anything saved from this editor, close.
            if let id = historyID, let entry = History.entries().first(where: { $0.id == id }) { History.remove(entry) }
            if let url = lastSavedURL, FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            window.close()
        case .openFolder:
            // Reveal the file saved from this editor, else just open the save folder.
            if let url = lastSavedURL, FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(Settings.saveFolder)
            }
        case .close: window.close()
        case .save:
            if let img = renderer.render(canvas.items), let url = try? Output.save(img) {
                lastSavedURL = url
                Output.playSound()
            }
        case .copy:
            if let img = renderer.render(canvas.items) {
                Output.copyToClipboard(img)
                if Settings.editorSaveOnCopy { lastSavedURL = try? Output.save(img) }
            }
            Output.playSound()
            if Settings.editorCloseAfterCopy { window.close() }
        }
    }

    /// Saves the annotated image to the save folder and opens it in the chosen app (PhotoCraft by default).
    private func openInExternalEditor() {
        let appURL = URL(fileURLWithPath: Settings.externalEditorPath)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            Permissions.alert("\(Settings.externalEditorName) was not found. Choose an editor app in Settings > Editor.")
            return
        }
        guard let img = renderer.render(canvas.items), let file = try? Output.save(img) else {
            Permissions.alert("Could not save the image to open it.")
            return
        }
        lastSavedURL = file
        let open = NSWorkspace.OpenConfiguration()
        open.activates = true   // bring the editor app to the front
        NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: open)
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
        let external = NSButton(); configure(external, symbol: "arrow.up.forward.app", title: "Open in \(Settings.externalEditorName)", action: #selector(externalTapped))
        let folder = NSButton()
        configure(folder, symbol: "folder", title: "", action: #selector(folderTapped))
        folder.imagePosition = .imageOnly
        folder.toolTip = "Open the folder (⌘O)"
        let trash = NSButton()
        configure(trash, symbol: "trash", title: "", action: #selector(deleteTapped))
        trash.imagePosition = .imageOnly
        trash.contentTintColor = .systemRed
        trash.toolTip = "Delete this capture (⌘⌫)"
        let save = NSButton(); configure(save, symbol: "square.and.arrow.down", title: "Save", action: #selector(saveTapped))
        let copy = NSButton(); configure(copy, symbol: "doc.on.doc", title: "Copy", action: #selector(copyTapped))
        copy.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [toolPicker, colorWell, undoButton, spacer, trash, folder, external, save, copy])
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
        colorWell.isEnabled = tool != .blur && tool != .crop
    }

    @objc private func toolChanged() { select(Tool(rawValue: toolPicker.selectedSegment) ?? .arrow) }
    @objc private func colorChanged() { canvas.setColor(colorWell.color, for: canvas.tool) }
    @objc private func undoTapped() { run(.undo) }
    @objc private func externalTapped() { run(.openExternal) }
    @objc private func deleteTapped() { run(.delete) }
    @objc private func folderTapped() { run(.openFolder) }
    @objc private func saveTapped() { run(.save) }
    @objc private func copyTapped() { run(.copy) }

    func windowWillClose(_ notification: Notification) {
        canvas.commitText()
        if let id = historyID { History.saveAnnotations(id, canvas.items) }
        onClose?(self)
    }
}
