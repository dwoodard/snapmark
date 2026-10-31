import AppKit
import AVFoundation
import ScreenCaptureKit

enum VideoQuality: Int, CaseIterable {
    case compact, high, maximum

    var title: String {
        switch self {
        case .compact: "Compact"
        case .high: "High"
        case .maximum: "Maximum"
        }
    }
    /// Bits per pixel per frame.
    var bitsPerPixel: Double {
        switch self {
        case .compact: 0.06
        case .high: 0.15
        case .maximum: 0.30
        }
    }
}

/// Records a screen region to an H.264 .mp4 with an explicit bitrate (the system recorder picks a very low one).
final class Recorder: NSObject, SCStreamDelegate, SCStreamOutput {
    private let queue = DispatchQueue(label: "snapmark.recorder")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var url: URL?
    // Touched only on `queue` once recording starts.
    private var sessionStarted = false
    private var finishing = false
    private(set) var isRecording = false

    /// Called when the stream ends on its own (display change, permission revoked).
    var onUnexpectedStop: (() -> Void)?

    func start(appKitRect: CGRect) async throws {
        let t = try await Capture.prepare(appKitRect: appKitRect)
        let config = t.config
        // H.264 needs even dimensions.
        config.width &= ~1
        config.height &= ~1
        let fps = Settings.videoFPS
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        let dir = Settings.saveFolder
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = dir.appendingPathComponent("Screen Recording \(f.string(from: Date())).mp4")

        let pixels = Double(config.width * config.height)
        let bitrate = min(max(pixels * Double(fps) * Settings.videoQuality.bitsPerPixel, 4_000_000), 80_000_000)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(bitrate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoExpectedSourceFrameRateKey: fps,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard w.canAdd(input) else { throw RecorderError.writerSetup }
        w.add(input)
        guard w.startWriting() else { throw w.error ?? RecorderError.writerSetup }

        let s = SCStream(filter: t.filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        queue.sync { sessionStarted = false; finishing = false }
        writer = w
        self.input = input
        self.url = url
        try await s.startCapture()
        stream = s
        isRecording = true
    }

    /// Stops and waits for the file to finish writing. Returns the file URL, or nil if no frames were captured.
    func stop() async -> URL? {
        guard let s = stream, let w = writer, let input else { return nil }
        isRecording = false
        stream = nil
        try? await s.stopCapture()

        let hadFrames: Bool = queue.sync {
            finishing = true
            return sessionStarted
        }
        defer { writer = nil; self.input = nil }
        guard hadFrames else {
            w.cancelWriting()
            return nil
        }
        // Static screens deliver few frames, so extend the clip to the moment recording stopped.
        w.endSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
        input.markAsFinished()
        await w.finishWriting()
        return w.status == .completed ? url : nil
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !finishing, sampleBuffer.isValid, let writer, let input else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        guard isRecording else { return }
        DispatchQueue.main.async { [weak self] in self?.onUnexpectedStop?() }
    }
}

enum RecorderError: LocalizedError {
    case writerSetup
    var errorDescription: String? { "Could not set up the video writer." }
}
