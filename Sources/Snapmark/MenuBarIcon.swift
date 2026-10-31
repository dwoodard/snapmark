import AppKit

/// The menu bar glyphs, drawn from the logo (see packaging/menubar). Falls back to SF Symbols when the
/// files are missing, for example when running the bare binary with `swift run`.
enum MenuBarIcon {
    /// Template image: macOS recolors it for light and dark menu bars.
    static var idle: NSImage { load("MenuBarIdle", template: true) ?? symbol("camera.viewfinder") }
    /// Red, with a stop square in the lens. Shown while recording: clicking it stops.
    static var recording: NSImage { load("MenuBarRecording", template: false) ?? symbol("stop.circle.fill") }

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
