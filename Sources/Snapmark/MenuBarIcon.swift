import AppKit

/// The menu bar glyphs, drawn from the logo (see packaging/menubar). Falls back to SF Symbols when the
/// files are missing, for example when running the bare binary with `swift run`.
enum MenuBarIcon {
    /// Template image: macOS recolors it for light and dark menu bars.
    static var idle: NSImage { load("MenuBarIdle", template: true) ?? symbol("camera.viewfinder") }
    /// Red, with a stop square in the lens. Shown while recording: clicking it stops.
    static var recording: NSImage { load("MenuBarRecording", template: false) ?? symbol("stop.circle.fill") }

    /// Lens filled in, like a shutter closing. Shown briefly after a capture.
    static var flash: NSImage { load("MenuBarFlash", template: true) ?? symbol("camera.fill") }

    enum State {
        case idle        // nothing happening
        case armed       // the picker or the Edit / Record bar is open
        case flash       // a capture was just taken
        case recording   // recording: click to stop
    }

    static func image(for state: State) -> NSImage {
        switch state {
        case .idle: idle
        case .armed: tinted(idle, .controlAccentColor)
        case .flash: tinted(flash, .systemGreen)
        case .recording: recording
        }
    }

    static func toolTip(for state: State) -> String? {
        switch state {
        case .armed: "Choose what to capture. Esc cancels."
        case .recording: "Recording. Click to stop."
        case .idle, .flash: nil
        }
    }

    static func apply(_ state: State, to button: NSStatusBarButton) {
        button.image = image(for: state)
        button.contentTintColor = nil
        button.toolTip = toolTip(for: state)
    }

    /// A colored copy of a template glyph. Painted ourselves so the color never depends on how the menu bar tints.
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let out = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        out.isTemplate = false
        return out
    }

    private static func load(_ name: String, template: Bool) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)   // the file is 36 px, so it is sharp on Retina menu bars
        image.isTemplate = template
        return image
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: "Snapmark") ?? NSImage()
    }
}
