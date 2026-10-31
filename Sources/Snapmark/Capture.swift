import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay
    var errorDescription: String? { "No display under the selected area." }
}

enum Capture {
    struct Result {
        let image: CGImage
        /// Pixels per point of the captured display (2 on Retina).
        let pixelScale: CGFloat
    }

    /// A display, filter and stream configuration for a screen rect, shared by screenshots and video.
    struct Target {
        let filter: SCContentFilter
        let config: SCStreamConfiguration
        let pixelScale: CGFloat
    }

    /// `appKitRect` is in global AppKit coordinates (origin bottom-left of the primary display).
    /// A selection spanning displays is clipped to the display it overlaps most.
    static func prepare(appKitRect r: CGRect) async throws -> Target {
        let primaryHeight = NSScreen.screens[0].frame.height
        let cg = CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        func overlap(_ d: SCDisplay) -> CGFloat {
            let i = d.frame.intersection(cg)
            return i.isNull ? 0 : i.width * i.height
        }
        guard let display = content.displays.max(by: { overlap($0) < overlap($1) }), overlap(display) > 0 else {
            throw CaptureError.noDisplay
        }

        let clip = display.frame.intersection(cg)
        // Snapmark's own overlays, bars and outlines must never appear in a capture.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: clip.minX - display.frame.minX, y: clip.minY - display.frame.minY,
                                   width: clip.width, height: clip.height)
        config.width = Int((clip.width * scale).rounded())
        config.height = Int((clip.height * scale).rounded())
        config.showsCursor = Settings.showCursor
        config.captureResolution = .best
        return Target(filter: filter, config: config, pixelScale: scale)
    }

    static func image(appKitRect r: CGRect) async throws -> Result {
        let t = try await prepare(appKitRect: r)
        let image = try await SCScreenshotManager.captureImage(contentFilter: t.filter, configuration: t.config)
        return Result(image: image, pixelScale: t.pixelScale)
    }
}
