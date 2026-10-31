import AppKit
import Vision

/// Reads text (OCR) and QR/barcodes from a captured image with the Vision framework.
enum Scanner {
    /// One recognized word. `rect` is in image pixels with a top-left origin (same space as the canvas).
    struct Word {
        let text: String
        let rect: CGRect
        let line: Int
    }

    struct Result {
        var text: String
        var words: [Word]
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

        var lines: [String] = []
        var words: [Word] = []
        let w = CGFloat(image.width), h = CGFloat(image.height)
        for obs in textRequest.results ?? [] {
            guard let cand = obs.topCandidates(1).first else { continue }
            let line = lines.count
            lines.append(cand.string)
            let str = cand.string
            var i = str.startIndex
            while i < str.endIndex {
                while i < str.endIndex, str[i].isWhitespace { i = str.index(after: i) }
                let start = i
                while i < str.endIndex, !str[i].isWhitespace { i = str.index(after: i) }
                guard start < i, let box = try? cand.boundingBox(for: start..<i) else { continue }
                let b = box.boundingBox   // normalized, bottom-left origin
                words.append(Word(text: String(str[start..<i]),
                                  rect: CGRect(x: b.minX * w, y: (1 - b.maxY) * h, width: b.width * w, height: b.height * h),
                                  line: line))
            }
        }
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
        return Result(text: text, words: words, codes: codes, links: links)
    }
}
