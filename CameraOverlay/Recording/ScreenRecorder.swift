import AVFoundation
import ScreenCaptureKit

/// Records one display to a movie with ScreenCaptureKit. Pause/resume works by shifting
/// timestamps so paused time is cut out of the movie instead of appearing as a freeze.
/// Mutable state is confined to `queue`, hence `@unchecked Sendable`.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Target {
        var displayID: CGDirectDisplayID
        /// Backing scale of the display, so the movie is captured at native pixel size.
        var scale: CGFloat
        /// Window numbers to leave out of the capture (our own control bar).
        var excludedWindowNumbers: [Int]
    }

    enum RecorderError: LocalizedError {
        case displayNotFound
        case notRecording

        var errorDescription: String? {
            switch self {
            case .displayNotFound: return "The display to record couldn't be found."
            case .notRecording: return "No recording is in progress."
            }
        }
    }

    /// Called off the main thread if the stream stops on its own (display unplugged, permission revoked…).
    var onStreamFailure: ((Error) -> Void)?

    private let queue = DispatchQueue(label: "CameraOverlay.recorder", qos: .userInitiated)

    // Queue-only state.
    private var stream: SCStream?
    private var writer: MovieWriter?
    private var isPaused = false
    private var pauseStartedAt: CMTime?
    private var pausedTotal = CMTime.zero

    func start(target: Target, frameRate: Int, microphone: Bool, outputURL: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == target.displayID }) ?? content.displays.first else {
            throw RecorderError.displayNotFound
        }
        let excluded = content.windows.filter { target.excludedWindowNumbers.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let configuration = SCStreamConfiguration()
        // H.264 wants even dimensions.
        configuration.width = Int(CGFloat(display.width) * target.scale) & ~1
        configuration.height = Int(CGFloat(display.height) * target.scale) & ~1
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.showsCursor = true
        configuration.queueDepth = 6
        configuration.capturesAudio = false

        var audioFormat: MovieWriter.AudioFormat?
        if microphone, #available(macOS 15.0, *), let device = AVCaptureDevice.default(for: .audio) {
            configuration.captureMicrophone = true
            configuration.microphoneCaptureDeviceID = device.uniqueID
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(device.activeFormat.formatDescription) {
                audioFormat = MovieWriter.AudioFormat(
                    sampleRate: asbd.pointee.mSampleRate,
                    channels: Int(asbd.pointee.mChannelsPerFrame)
                )
            }
        }

        let writer = try MovieWriter(
            url: outputURL,
            width: configuration.width,
            height: configuration.height,
            frameRate: frameRate,
            audio: audioFormat
        )

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if audioFormat != nil, #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }

        queue.sync {
            self.stream = stream
            self.writer = writer
            self.isPaused = false
            self.pauseStartedAt = nil
            self.pausedTotal = .zero
        }

        do {
            try await stream.startCapture()
        } catch {
            queue.sync {
                self.stream = nil
                self.writer = nil
            }
            writer.finish { _ in }
            throw error
        }
    }

    func pause() {
        queue.async {
            guard !self.isPaused else { return }
            self.isPaused = true
            self.pauseStartedAt = CMClockGetTime(CMClockGetHostTimeClock())
        }
    }

    func resume() {
        queue.async {
            guard self.isPaused else { return }
            if let start = self.pauseStartedAt {
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                self.pausedTotal = CMTimeAdd(self.pausedTotal, CMTimeSubtract(now, start))
            }
            self.pauseStartedAt = nil
            self.isPaused = false
        }
    }

    /// Stops capturing and finalizes the movie. Returns the saved file.
    func stop() async throws -> URL {
        let stream = queue.sync { self.stream }
        if let stream {
            try? await stream.stopCapture() // already-stopped streams throw; the writer still finalizes
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let writer = self.writer else {
                    continuation.resume(throwing: RecorderError.notRecording)
                    return
                }
                self.stream = nil
                self.writer = nil
                writer.finish { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: writer.url)
                    }
                }
            }
        }
    }

    // MARK: SCStreamOutput (recorder queue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let writer, !isPaused, sampleBuffer.isValid else { return }

        if type == .screen {
            // Only frames that carry new content; idle/blank frames have no image to encode.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusValue = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusValue),
                  status == .complete,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }
            let time = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), pausedTotal)
            writer.appendVideo(pixelBuffer, at: time)
            return
        }

        if #available(macOS 15.0, *), type == .microphone {
            writer.appendAudio(sampleBuffer, shiftedBy: pausedTotal)
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamFailure?(error)
    }
}
