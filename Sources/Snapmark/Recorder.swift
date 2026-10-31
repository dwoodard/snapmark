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
    private var audioInput: AVAssetWriterInput?
    private var mixer: AudioMixer?
    private var wantsSystemAudio = false
    private var wantsMicrophone = false
    private var url: URL?
    // Touched only on `queue` once recording starts.
    private var sessionStarted = false
    private var finishing = false
    private(set) var isRecording = false

    /// Called when the stream ends on its own (display change, permission revoked).
    var onUnexpectedStop: (() -> Void)?

    func start(appKitRect: CGRect, systemAudio: Bool, microphone: Bool) async throws {
        if microphone, !(await AVCaptureDevice.requestAccess(for: .audio)) { throw RecorderError.microphoneDenied }
        wantsSystemAudio = systemAudio
        wantsMicrophone = microphone
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
        if systemAudio || microphone {
            config.sampleRate = 48000
            config.channelCount = 2
        }
        if systemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
        }
        if microphone {
            config.captureMicrophone = true
            config.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        }

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
        if systemAudio || microphone {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000,
            ]
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            ai.expectsMediaDataInRealTime = true
            guard w.canAdd(ai) else { throw RecorderError.writerSetup }
            w.add(ai)
            audioInput = ai
        } else {
            audioInput = nil
        }
        guard w.startWriting() else { throw w.error ?? RecorderError.writerSetup }

        let s = SCStream(filter: t.filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if systemAudio { try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if microphone { try s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        queue.sync { sessionStarted = false; finishing = false; mixer = nil }
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
            mixer?.flush(force: true)
            return sessionStarted
        }
        let audio = audioInput
        defer { writer = nil; self.input = nil; audioInput = nil; mixer = nil }
        guard hadFrames else {
            w.cancelWriting()
            return nil
        }
        // Static screens deliver few frames, so extend the clip to the moment recording stopped.
        w.endSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
        input.markAsFinished()
        audio?.markAsFinished()
        await w.finishWriting()
        return w.status == .completed ? url : nil
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !finishing, sampleBuffer.isValid, let writer, let input else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: raw) == .complete else { return }
            if !sessionStarted {
                let origin = sampleBuffer.presentationTimeStamp
                writer.startSession(atSourceTime: origin)
                sessionStarted = true
                if let audioInput {
                    var sources: Set<AudioMixer.Source> = []
                    if wantsSystemAudio { sources.insert(.system) }
                    if wantsMicrophone { sources.insert(.mic) }
                    mixer = AudioMixer(origin: origin, sources: sources) { buffer in
                        if audioInput.isReadyForMoreMediaData { audioInput.append(buffer) }
                    }
                }
            }
            if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
        case .audio:
            mixer?.add(sampleBuffer, from: .system)
        case .microphone:
            mixer?.add(sampleBuffer, from: .mic)
        @unknown default:
            break
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        guard isRecording else { return }
        DispatchQueue.main.async { [weak self] in self?.onUnexpectedStop?() }
    }
}

enum RecorderError: LocalizedError {
    case writerSetup
    case microphoneDenied
    var errorDescription: String? {
        switch self {
        case .writerSetup: "Could not set up the video writer."
        case .microphoneDenied: "Microphone access is off. Allow Snapmark in System Settings > Privacy & Security > Microphone, or turn Mic off."
        }
    }
}

/// Mixes system audio and microphone into one 48 kHz stereo stream on a shared timeline,
/// so the video gets a single audio track that plays everywhere.
final class AudioMixer {
    enum Source { case system, mic }

    private let rate = 48000.0
    private let origin: CMTime
    private let sources: Set<Source>
    private let sink: (CMSampleBuffer) -> Void
    private var left: [Float] = []
    private var right: [Float] = []
    private var emitted = 0                 // frames already sent; left/right start at this frame
    private var lastEnd: [Source: Int] = [:]

    init(origin: CMTime, sources: Set<Source>, sink: @escaping (CMSampleBuffer) -> Void) {
        self.origin = origin
        self.sources = sources
        self.sink = sink
    }

    func add(_ buffer: CMSampleBuffer, from source: Source) {
        guard sources.contains(source), let (l, r) = AudioMixer.stereo(from: buffer) else { return }
        var start = Int(((buffer.presentationTimeStamp - origin).seconds * rate).rounded())
        var skip = 0
        if start < emitted { skip = emitted - start; start = emitted }   // late head: drop it
        guard skip < l.count else { return }
        let count = l.count - skip
        let need = start - emitted + count
        if left.count < need {
            left.append(contentsOf: [Float](repeating: 0, count: need - left.count))
            right.append(contentsOf: [Float](repeating: 0, count: need - right.count))
        }
        for i in 0..<count {
            left[start - emitted + i] += l[skip + i]
            right[start - emitted + i] += r[skip + i]
        }
        lastEnd[source] = max(lastEnd[source] ?? 0, start + count)
        flush(force: false)
    }

    /// Sends everything both sources have delivered. A stalled source delays output by at most half a second.
    func flush(force: Bool) {
        let ends = sources.map { lastEnd[$0] ?? emitted }
        guard let maxEnd = ends.max(), let minEnd = ends.min() else { return }
        let target = force ? maxEnd : max(minEnd, maxEnd - Int(rate / 2))
        while emitted < target {
            let n = min(4800, target - emitted)
            var interleaved = [Float](repeating: 0, count: n * 2)
            for i in 0..<n {
                interleaved[i * 2] = max(-1, min(1, left[i]))
                interleaved[i * 2 + 1] = max(-1, min(1, right[i]))
            }
            if let sb = AudioMixer.makeBuffer(interleaved, frames: n, origin: origin, index: emitted) { sink(sb) }
            left.removeFirst(n)
            right.removeFirst(n)
            emitted += n
        }
    }

    private static func stereo(from sb: CMSampleBuffer) -> ([Float], [Float])? {
        guard let fd = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32,
              abs(asbd.mSampleRate - 48000) < 1 else { return nil }
        var size = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: &size, bufferListOut: nil, bufferListSize: 0,
                                                                blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard size > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: size,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block)
        guard status == noErr else { return nil }

        let frames = CMSampleBufferGetNumSamples(sb)
        var l = [Float](repeating: 0, count: frames), r = l
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let channels = Int(asbd.mChannelsPerFrame)
        if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
            for (i, b) in buffers.enumerated() where i < 2 {
                guard let data = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let n = min(frames, Int(b.mDataByteSize) / 4)
                for f in 0..<n { if i == 0 { l[f] = data[f] } else { r[f] = data[f] } }
            }
            if buffers.count == 1 { r = l }
        } else if let b = buffers.first, let data = b.mData?.assumingMemoryBound(to: Float.self), channels > 0 {
            let n = min(frames, Int(b.mDataByteSize) / (4 * channels))
            for f in 0..<n {
                l[f] = data[f * channels]
                r[f] = channels > 1 ? data[f * channels + 1] : data[f * channels]
            }
        }
        return (l, r)
    }

    private static func makeBuffer(_ interleaved: [Float], frames: Int, origin: CMTime, index: Int) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                                               mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                             magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        let bytes = interleaved.count * 4
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block else { return nil }
        let copied = interleaved.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        }
        guard copied == noErr else { return nil }
        var sb: CMSampleBuffer?
        let pts = CMTimeAdd(origin, CMTime(value: CMTimeValue(index), timescale: 48000))
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format,
                                                                   sampleCount: frames, presentationTimeStamp: pts,
                                                                   packetDescriptions: nil, sampleBufferOut: &sb) == noErr else { return nil }
        return sb
    }
}
