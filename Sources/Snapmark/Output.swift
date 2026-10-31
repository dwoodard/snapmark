import AppKit

enum Output {
    static func copyToClipboard(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    @discardableResult
    static func save(_ image: CGImage) throws -> URL {
        let dir = Settings.saveFolder
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let format = Settings.imageFormat
        let url = dir.appendingPathComponent("\(Settings.filenamePrefix) \(f.string(from: Date())).\(format.ext)")
        let rep = NSBitmapImageRep(cgImage: image)
        let data = format == .png
            ? rep.representation(using: .png, properties: [:])
            : rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        try data?.write(to: url)
        return url
    }

    static func playSound() {
        guard Settings.playSound else { return }
        // The system camera shutter, played quietly. Falls back to Tink if the file is missing.
        let shutter = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif"
        let sound = NSSound(contentsOfFile: shutter, byReference: true) ?? NSSound(named: "Tink")
        sound?.volume = 0.35
        sound?.play()
    }
}
