import AppKit
import AVFoundation

/// Codable form of an annotation (color stored as sRGB components).
struct StoredAnnotation: Codable {
    var tool: Int
    var sx, sy, ex, ey: Double
    var rgba: [Double]
    var text: String
    var applied: Bool?

    init(_ a: Annotation) {
        tool = a.tool.rawValue
        sx = a.start.x; sy = a.start.y; ex = a.end.x; ey = a.end.y
        let c = a.color.usingColorSpace(.sRGB) ?? a.color
        rgba = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map(Double.init)
        text = a.text
        applied = a.applied
    }

    var annotation: Annotation? {
        guard let t = Tool(rawValue: tool), rgba.count == 4 else { return nil }
        return Annotation(tool: t, start: CGPoint(x: sx, y: sy), end: CGPoint(x: ex, y: ey),
                          color: NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]), text: text,
                          applied: applied ?? false)
    }
}

enum HistoryKind { case image, video }

struct HistoryEntry {
    let id: String
    let date: Date
    let kind: HistoryKind
    let videoURL: URL?
    var dir: URL { History.root.appendingPathComponent(id, isDirectory: true) }
    var thumbnail: NSImage? { NSImage(contentsOf: dir.appendingPathComponent("thumb.png")) }
}

/// Recent captures kept in ~/Library/Application Support/Snapmark/History.
enum History {
    private struct Meta: Codable { var date: Date; var pixelScale: Double; var kind: String?; var videoPath: String? }

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapmark/History", isDirectory: true)
    }

    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    /// Stores the capture and returns its id, or nil when history is off.
    static func add(_ result: Capture.Result) -> String? {
        let limit = Settings.historyLimit
        guard limit > 0 else { return nil }
        let id = UUID().uuidString
        let dir = root.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let rep = NSBitmapImageRep(cgImage: result.image)
            try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("original.png"))
            try thumbnailPNG(result.image, playBadge: false)?.write(to: dir.appendingPathComponent("thumb.png"))
            try encoder.encode(Meta(date: Date(), pixelScale: Double(result.pixelScale), kind: "image", videoPath: nil)).write(to: dir.appendingPathComponent("meta.json"))
        } catch {
            return nil
        }
        prune(keeping: limit)
        return id
    }

    static func entries() -> [HistoryEntry] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
                  let meta = try? decoder.decode(Meta.self, from: data) else { return nil }
            let isVideo = meta.kind == "video"
            return HistoryEntry(id: dir.lastPathComponent, date: meta.date, kind: isVideo ? .video : .image,
                                videoURL: meta.videoPath.map { URL(fileURLWithPath: $0) })
        }.sorted { $0.date > $1.date }
    }

    static func load(_ entry: HistoryEntry) -> (capture: Capture.Result, annotations: [Annotation])? {
        guard let data = try? Data(contentsOf: entry.dir.appendingPathComponent("original.png")),
              let image = NSBitmapImageRep(data: data)?.cgImage,
              let metaData = try? Data(contentsOf: entry.dir.appendingPathComponent("meta.json")),
              let meta = try? decoder.decode(Meta.self, from: metaData) else { return nil }
        let stored = (try? Data(contentsOf: entry.dir.appendingPathComponent("annotations.json")))
            .flatMap { try? JSONDecoder().decode([StoredAnnotation].self, from: $0) } ?? []
        return (Capture.Result(image: image, pixelScale: CGFloat(meta.pixelScale)), stored.compactMap(\.annotation))
    }

    static func saveAnnotations(_ id: String, _ items: [Annotation]) {
        let dir = root.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try? JSONEncoder().encode(items.map(StoredAnnotation.init)).write(to: dir.appendingPathComponent("annotations.json"))
    }

    /// Records a finished video (the file itself stays in the save folder). Returns its history id.
    static func addVideo(_ url: URL) async -> String? {
        let limit = Settings.historyLimit
        guard limit > 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        var frame = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
        if frame == nil { frame = try? await generator.image(at: .zero).image }
        guard let frame else { return nil }

        let id = UUID().uuidString
        let dir = root.appendingPathComponent(id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try thumbnailPNG(frame, playBadge: true)?.write(to: dir.appendingPathComponent("thumb.png"))
            try encoder.encode(Meta(date: Date(), pixelScale: 1, kind: "video", videoPath: url.path)).write(to: dir.appendingPathComponent("meta.json"))
        } catch {
            return nil
        }
        prune(keeping: limit)
        return id
    }

    /// Drops history entries that point at this video file (used when the file is replaced in place).
    static func removeVideoEntries(for url: URL) {
        for e in entries() where e.kind == .video && e.videoURL?.path == url.path { remove(e) }
    }

    static func remove(_ entry: HistoryEntry) { try? FileManager.default.removeItem(at: entry.dir) }

    static func clear() { try? FileManager.default.removeItem(at: root) }

    private static func prune(keeping limit: Int) {
        let all = entries()
        for kind in [HistoryKind.image, .video] {
            for e in all.filter({ $0.kind == kind }).dropFirst(limit) { try? FileManager.default.removeItem(at: e.dir) }
        }
    }

    private static func thumbnailPNG(_ image: CGImage, playBadge: Bool) -> Data? {
        let maxSide: CGFloat = 160
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let s = min(1, maxSide / max(w, h))
        let size = NSSize(width: max(1, (w * s).rounded()), height: max(1, (h * s).rounded()))
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        NSImage(cgImage: image, size: size).draw(in: NSRect(origin: .zero, size: size))
        if playBadge {
            let d = min(size.width, size.height) * 0.5
            let circle = NSRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: circle).fill()
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: circle.minX + d * 0.38, y: circle.minY + d * 0.27))
            tri.line(to: NSPoint(x: circle.minX + d * 0.38, y: circle.minY + d * 0.73))
            tri.line(to: NSPoint(x: circle.minX + d * 0.74, y: circle.midY))
            tri.close()
            NSColor.white.setFill()
            tri.fill()
        }
        thumb.unlockFocus()
        guard let tiff = thumb.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
