import AppKit
import AVKit

/// Plays a recording in-app. Trim uses the system trim handles and saves a copy.
final class VideoViewerController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let playerView = AVPlayerView()
    private let trimButton = NSButton()
    private(set) var url: URL
    var onClose: ((VideoViewerController) -> Void)?
    /// Called after a trim is written. `replaced` is true when the original file was overwritten.
    var onSaved: ((URL, Bool) -> Void)?
    /// Called after the video was moved to the Trash.
    var onDeleted: ((URL) -> Void)?

    init(url: URL) {
        self.url = url
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = url.lastPathComponent
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 520, height: 360)

        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: url)

        let bar = buildBar()
        let content = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        playerView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)
        content.addSubview(playerView)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
            playerView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            playerView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        window.contentView = content
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        playerView.player?.play()
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Bar

    private func buildBar() -> NSView {
        func button(_ b: NSButton, _ symbol: String, _ title: String, _ action: Selector) {
            b.title = title
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            b.imagePosition = .imageLeading
            b.bezelStyle = .texturedRounded
            b.target = self
            b.action = action
        }
        button(trimButton, "scissors", "Trim", #selector(trim))
        let finder = NSButton(); button(finder, "folder", "Show in Finder", #selector(showInFinder))
        let copy = NSButton(); button(copy, "doc.on.doc", "Copy File", #selector(copyFile))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let trash = NSButton(); button(trash, "trash", "Delete", #selector(deleteVideo))
        trash.contentTintColor = .systemRed
        trash.keyEquivalent = "\u{7f}"
        trash.keyEquivalentModifierMask = .command
        trash.toolTip = "Move this video to the Trash (⌘⌫)"
        let stack = NSStackView(views: [trimButton, spacer, trash, finder, copy])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        return stack
    }

    @objc private func deleteVideo() {
        playerView.player?.pause()
        playerView.player = nil
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            Permissions.alert("Could not move the video to the Trash: \(error.localizedDescription)")
            return
        }
        onDeleted?(url)
        window.close()
    }

    @objc private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyFile() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    @objc private func trim() {
        guard playerView.canBeginTrimming else { return }
        playerView.beginTrimming { [weak self] result in
            guard result == .okButton else { return }
            Task { @MainActor in await self?.exportTrimmed() }
        }
    }

    @MainActor private func exportTrimmed() async {
        guard let item = playerView.player?.currentItem else { return }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return }
        let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : duration
        guard end > start, let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return }
        session.timeRange = CMTimeRange(start: start, end: end)

        let alert = NSAlert()
        alert.messageText = "Save the trimmed video"
        alert.informativeText = "Replace the original file, or keep it and save the trim as a copy?"
        alert.addButton(withTitle: "Replace Original")
        alert.addButton(withTitle: "Save as Copy")
        alert.addButton(withTitle: "Cancel")
        let choice = alert.runModal()
        guard choice != .alertThirdButtonReturn else { return }
        let replace = choice == .alertFirstButtonReturn

        // Export beside the original first, so a failed export never touches it.
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".snapmark-trim-\(UUID().uuidString).mp4")
        trimButton.isEnabled = false
        window.title = "Saving trimmed video…"
        defer { trimButton.isEnabled = true }
        do {
            try await session.export(to: temp, as: .mp4)
            let result: URL
            if replace {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
                result = url
            } else {
                result = uniqueTrimmedURL()
                try FileManager.default.moveItem(at: temp, to: result)
            }
            url = result
            playerView.player = AVPlayer(url: result)
            playerView.player?.play()
            window.title = result.lastPathComponent
            onSaved?(result, replace)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            window.title = url.lastPathComponent
            Permissions.alert("Trim failed: \(error.localizedDescription)")
        }
    }

    private func uniqueTrimmedURL() -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var out = dir.appendingPathComponent("\(base) (trimmed).mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base) (trimmed \(n)).mp4")
            n += 1
        }
        return out
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        playerView.player = nil
        onClose?(self)
    }
}
