import AVFoundation

/// Writes screen frames (and optional microphone audio) to a QuickTime movie.
/// Not thread-safe: call every method from the same serial queue.
final class MovieWriter {
    struct AudioFormat: Equatable {
        var sampleRate: Double
        var channels: Int
    }

    enum WriterError: LocalizedError {
        case noFrames
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noFrames: return "No video frames were captured."
            case .failed(let message): return message
            }
        }
    }

    let url: URL

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let audioFormat: AudioFormat?
    private var audioDisabled = false
    private var sessionStarted = false
    private var lastVideoTime = CMTime.invalid

    init(url: URL, width: Int, height: Int, frameRate: Int, audio: AudioFormat?) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Rough H.264 budget: ~0.07 bits per pixel per frame, never below 8 Mbit/s.
        let bitrate = max(8_000_000, Int(Double(width * height) * Double(frameRate) * 0.07))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        writer.add(videoInput)

        if let audio, (1...2).contains(audio.channels) {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: audio.sampleRate,
                AVNumberOfChannelsKey: audio.channels,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
            audioFormat = audio
        } else {
            audioInput = nil
            audioFormat = nil
        }

        guard writer.startWriting() else {
            throw WriterError.failed(writer.error?.localizedDescription ?? "Couldn't start writing the movie.")
        }
    }

    /// `time` must already have paused time subtracted; frames that don't move forward are dropped.
    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard writer.status == .writing else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        if lastVideoTime.isValid, time <= lastVideoTime { return }
        if pixelAdaptor.append(pixelBuffer, withPresentationTime: time) {
            lastVideoTime = time
        }
    }

    /// Shifts the buffer's timestamps back by `offset` (accumulated paused time) and appends it.
    /// Audio arriving before the first video frame is dropped so the session start stays video-defined.
    func appendAudio(_ sampleBuffer: CMSampleBuffer, shiftedBy offset: CMTime) {
        guard let audioInput, !audioDisabled, sessionStarted, writer.status == .writing else { return }

        // The encoder was configured from the device's reported format; if the stream
        // actually delivers a different channel count, skip audio instead of failing the movie.
        if let format = audioFormat,
           let description = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
           Int(asbd.pointee.mChannelsPerFrame) != format.channels {
            audioDisabled = true
            return
        }

        guard audioInput.isReadyForMoreMediaData else { return }

        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing) == noErr else { return }
        timing.presentationTimeStamp = CMTimeSubtract(timing.presentationTimeStamp, offset)
        timing.decodeTimeStamp = .invalid

        var shifted: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &shifted
        )
        guard status == noErr, let shifted else { return }
        audioInput.append(shifted)
    }

    func finish(completion: @escaping (Error?) -> Void) {
        guard sessionStarted, writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            completion(writer.error ?? WriterError.noFrames)
            return
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [writer] in
            completion(writer.status == .completed ? nil : (writer.error ?? WriterError.failed("The movie couldn't be saved.")))
        }
    }
}
