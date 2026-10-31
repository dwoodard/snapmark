import AppKit
import UniformTypeIdentifiers

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

    static var historyLimit: Int { get { value("historyLimit", 10) } set { store("historyLimit", newValue) } }
    static var playSound: Bool { get { value("playSound", false) } set { store("playSound", newValue) } }

    // MARK: Capture

    static var copyToClipboard: Bool { get { value("copyToClipboard", true) } set { store("copyToClipboard", newValue) } }
    static var saveToFile: Bool { get { value("saveToFile", true) } set { store("saveToFile", newValue) } }
    static var showCursor: Bool { get { value("showCursor", false) } set { store("showCursor", newValue) } }
    static var filenamePrefix: String { get { value("filenamePrefix", "Screenshot") } set { store("filenamePrefix", newValue) } }
    static var openViewerAfterRecording: Bool { get { value("openViewerAfterRecording", true) } set { store("openViewerAfterRecording", newValue) } }
    static var recordSystemAudio: Bool { get { value("recordSystemAudio", false) } set { store("recordSystemAudio", newValue) } }
    static var recordMicrophone: Bool { get { value("recordMicrophone", false) } set { store("recordMicrophone", newValue) } }
    static var videoQuality: VideoQuality {
        get { VideoQuality(rawValue: value("videoQuality", VideoQuality.high.rawValue)) ?? .high }
        set { store("videoQuality", newValue.rawValue) }
    }
    static var videoFPS: Int { get { value("videoFPS", 30) } set { store("videoFPS", newValue) } }
    static var aspectIndex: Int { get { value("aspectIndex", 0) } set { store("aspectIndex", newValue) } }
    static var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: value("imageFormat", "png")) ?? .png }
        set { store("imageFormat", newValue.rawValue) }
    }

    // MARK: Editor

    /// App used by the editor's "Open in…" button.
    static var externalEditorPath: String {
        get { value("externalEditorPath", "/Applications/PhotoCraft.app") }
        set { store("externalEditorPath", newValue) }
    }
    static var externalEditorName: String {
        FileManager.default.displayName(atPath: externalEditorPath).replacingOccurrences(of: ".app", with: "")
    }

    private static func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseExternalEditor() { if let p = chooseApp() { externalEditorPath = p } }

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
