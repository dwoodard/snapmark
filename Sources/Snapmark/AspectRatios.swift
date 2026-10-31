import AppKit

struct AspectChoice {
    let title: String
    /// Width / height for a fixed ratio. Nil for Free and Smart.
    let ratio: CGFloat?
    let smart: Bool
}

enum AspectRatios {
    static let all: [AspectChoice] = [
        AspectChoice(title: "Free", ratio: nil, smart: false),
        AspectChoice(title: "Smart (snap to nearest)", ratio: nil, smart: true),
        AspectChoice(title: "1:1", ratio: 1, smart: false),
        AspectChoice(title: "4:3", ratio: 4.0 / 3, smart: false),
        AspectChoice(title: "3:2", ratio: 3.0 / 2, smart: false),
        AspectChoice(title: "16:9", ratio: 16.0 / 9, smart: false),
        AspectChoice(title: "16:10", ratio: 16.0 / 10, smart: false),
        AspectChoice(title: "21:9", ratio: 21.0 / 9, smart: false),
        AspectChoice(title: "3:4", ratio: 3.0 / 4, smart: false),
        AspectChoice(title: "2:3", ratio: 2.0 / 3, smart: false),
        AspectChoice(title: "9:16", ratio: 9.0 / 16, smart: false),
    ]

    /// Ratios Smart mode can snap to and the overlay label can name.
    private static let common: [(w: CGFloat, h: CGFloat)] = [
        (1, 1), (4, 3), (3, 2), (16, 9), (16, 10), (21, 9), (5, 4),
        (3, 4), (2, 3), (9, 16), (10, 16), (4, 5),
    ]

    static var current: AspectChoice { all[min(max(Settings.aspectIndex, 0), all.count - 1)] }

    /// Closest common ratio (width / height) within `tolerance`, or nil.
    private static func closest(w: CGFloat, h: CGFloat, tolerance: CGFloat) -> (w: CGFloat, h: CGFloat)? {
        guard w > 0, h > 0 else { return nil }
        let r = w / h
        let best = common.min { abs(log(r / ($0.w / $0.h))) < abs(log(r / ($1.w / $1.h))) }
        guard let best, abs(log(r / (best.w / best.h))) < tolerance else { return nil }
        return best
    }

    /// Smart snapping target. Ignores tiny selections so it does not jitter at the start of a drag.
    static func snapRatio(w: CGFloat, h: CGFloat) -> CGFloat? {
        guard w > 40, h > 40, let c = closest(w: w, h: h, tolerance: 0.04) else { return nil }
        return c.w / c.h
    }

    /// "16:9" when the size matches a common ratio, else "".
    static func label(w: CGFloat, h: CGFloat) -> String {
        guard let c = closest(w: w, h: h, tolerance: 0.015) else { return "" }
        return "\(Int(c.w)):\(Int(c.h))"
    }
}
