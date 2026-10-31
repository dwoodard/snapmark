import AppKit

enum ImageFormat: String, CaseIterable {
    case png, jpeg
    var ext: String { self == .png ? "png" : "jpg" }
    var title: String { self == .png ? "PNG" : "JPEG" }
}

enum Settings {
    private static let defaults = UserDefaults.standard
    private static func value<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: key) as? T ?? fallback }
    private static func store(_ key: String, _ v: Any) { defaults.set(v, forKey: key) }

    // MARK: General

    /// Default: the system screenshot location if set, else ~/Pictures/Screenshots.
    static var saveFolder: URL {
        get {
            if let p = defaults.string(forKey: "saveFolderPath") { return URL(fileURLWithPath: p, isDirectory: true) }
            if let p = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
                return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots", isDirectory: true)
        }
        set { store("saveFolderPath", newValue.path) }
    }

    static var playSound: Bool { get { value("playSound", true) } set { store("playSound", newValue) } }

    // MARK: Capture

    static var copyToClipboard: Bool { get { value("copyToClipboard", true) } set { store("copyToClipboard", newValue) } }
    static var saveToFile: Bool { get { value("saveToFile", true) } set { store("saveToFile", newValue) } }
    static var showCursor: Bool { get { value("showCursor", false) } set { store("showCursor", newValue) } }
    static var filenamePrefix: String { get { value("filenamePrefix", "Screenshot") } set { store("filenamePrefix", newValue) } }
    static var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: value("imageFormat", "png")) ?? .png }
        set { store("imageFormat", newValue.rawValue) }
    }

    // MARK: Editor

    static var defaultTool: Int { get { value("defaultTool", Tool.arrow.rawValue) } set { store("defaultTool", newValue) } }
    static var lineWidth: Double { get { value("lineWidth", 3.0) } set { store("lineWidth", newValue) } }
    static var textSize: Double { get { value("textSize", 18.0) } set { store("textSize", newValue) } }
    static var blurStrength: Double { get { value("blurStrength", 10.0) } set { store("blurStrength", newValue) } }
    static var editorCloseAfterCopy: Bool { get { value("editorCloseAfterCopy", true) } set { store("editorCloseAfterCopy", newValue) } }
    static var editorSaveOnCopy: Bool { get { value("editorSaveOnCopy", false) } set { store("editorSaveOnCopy", newValue) } }

    // MARK: Shortcuts

    static func hotkeyKey(_ k: HotkeyTap.Key) -> String {
        switch k {
        case .quickFull: "hotkey.quickFull"
        case .quickRegion: "hotkey.quickRegion"
        case .editRegion: "hotkey.editRegion"
        }
    }
    static func hotkeyEnabled(_ k: HotkeyTap.Key) -> Bool { value(hotkeyKey(k), true) }
    static func setHotkey(_ k: HotkeyTap.Key, enabled: Bool) { store(hotkeyKey(k), enabled) }

    static func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveFolder
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url }
    }
}
