import AppKit
import Vision

/// Reads text (OCR) and QR/barcodes from a captured image with the Vision framework.
enum Scanner {
    struct Result {
        var text: String
        /// QR / barcode payloads, in detection order.
        var codes: [String]
        /// Web links found in the text and the codes, de-duplicated, in order.
        var links: [URL]
        var isEmpty: Bool { text.isEmpty && codes.isEmpty }
    }

    /// Blocking: call off the main thread.
    static func scan(_ image: CGImage) -> Result {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let codeRequest = VNDetectBarcodesRequest()

        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([textRequest, codeRequest])

        let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        var codes: [String] = []
        for payload in (codeRequest.results ?? []).compactMap(\.payloadStringValue) where !codes.contains(payload) {
            codes.append(payload)
        }

        var links: [URL] = []
        func add(_ url: URL) { if !links.contains(url) { links.append(url) } }
        for code in codes {
            if let url = URL(string: code), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) { add(url) }
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let url = m.url { add(url) }
            }
        }
        return Result(text: text, codes: codes, links: links)
    }
}
