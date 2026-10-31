import AppKit

/// Menu row showing the latest captures as a horizontal strip of thumbnails.
final class RecentBarView: NSView {
    static let count = 3
    private static let slot = NSSize(width: 104, height: 68)
    private static let pad: CGFloat = 10

    private let onSelect: (String) -> Void

    private final class ThumbButton: NSButton {
        var entryID = ""
    }

    init(entries: [HistoryEntry], onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        let s = RecentBarView.slot, p = RecentBarView.pad
        let width = CGFloat(RecentBarView.count) * s.width + CGFloat(RecentBarView.count + 1) * p
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: s.height + p))

        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true

        for (i, e) in entries.prefix(RecentBarView.count).enumerated() {
            let b = ThumbButton(frame: NSRect(x: p + CGFloat(i) * (s.width + p), y: p / 2, width: s.width, height: s.height))
            b.entryID = e.id
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.imageScaling = .scaleProportionallyUpOrDown
            b.image = e.thumbnail
            b.toolTip = f.string(from: e.date)
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.layer?.masksToBounds = true
            b.layer?.borderWidth = 1
            b.layer?.borderColor = NSColor.separatorColor.cgColor
            b.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            b.target = self
            b.action = #selector(tapped(_:))
            addSubview(b)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped(_ sender: ThumbButton) {
        enclosingMenuItem?.menu?.cancelTracking()
        onSelect(sender.entryID)
    }
}
