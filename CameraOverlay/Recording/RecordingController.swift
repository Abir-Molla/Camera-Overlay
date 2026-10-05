import AppKit
import AVFoundation
import Combine

/// Drives the record → countdown → pause → stop & save flow and publishes the state the UI shows.
/// Main thread only.
final class RecordingController: ObservableObject {
    enum State: Equatable {
        case idle
        case countingDown(Int)
        case starting
        case recording
        case paused
        case saving

        /// True while a movie is being captured (paused counts).
        var isCapturing: Bool { self == .recording || self == .paused }
    }

    struct CaptureTarget {
        var screen: NSScreen
        var excludedWindowNumbers: [Int]
    }

    static let countdownSeconds = 3
    static let frameRate = 30

    @Published private(set) var state: State = .idle
    /// Seconds of recorded footage (paused time excluded).
    @Published private(set) var elapsed: TimeInterval = 0

    /// Supplies the screen to record and windows to leave out. Set by the overlay controller.
    var captureTarget: (() -> CaptureTarget?)?

    private let recorder = ScreenRecorder()
    private var countdownTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var segmentStart: Date?
    private var elapsedBeforeSegment: TimeInterval = 0

    init() {
        recorder.onStreamFailure = { [weak self] error in
            DispatchQueue.main.async { self?.streamFailed(error) }
        }
    }

    // MARK: Actions

    func start(withCountdown: Bool) {
        guard state == .idle, ensureScreenRecordingPermission() else { return }
        guard withCountdown else {
            begin()
            return
        }
        countdownTask = Task { @MainActor [weak self] in
            for remaining in stride(from: Self.countdownSeconds, to: 0, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.state = .countingDown(remaining)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.begin()
        }
    }

    func cancelCountdown() {
        guard case .countingDown = state else { return }
        countdownTask?.cancel()
        countdownTask = nil
        state = .idle
    }

    func togglePause() {
        switch state {
        case .recording:
            recorder.pause()
            elapsedBeforeSegment = currentElapsed()
            segmentStart = nil
            stopElapsedTimer()
            elapsed = elapsedBeforeSegment
            state = .paused
        case .paused:
            recorder.resume()
            segmentStart = Date()
            startElapsedTimer()
            state = .recording
        default:
            break
        }
    }

    /// Finalizes the movie and reveals it in Finder. During a countdown this just cancels.
    func stopAndSave(completion: ((URL?) -> Void)? = nil) {
        switch state {
        case .countingDown:
            cancelCountdown()
            completion?(nil)
            return
        case .recording, .paused:
            break
        default:
            completion?(nil)
            return
        }

        stopElapsedTimer()
        elapsed = currentElapsed()
        segmentStart = nil
        state = .saving

        Task { @MainActor [weak self] in
            guard let self else {
                completion?(nil)
                return
            }
            do {
                let url = try await self.recorder.stop()
                self.state = .idle
                NSWorkspace.shared.activateFileViewerSelecting([url])
                completion?(url)
            } catch {
                self.state = .idle
                self.presentError(error)
                completion?(nil)
            }
        }
    }

    // MARK: Private

    private func begin() {
        countdownTask = nil
        guard let target = captureTarget?() else {
            state = .idle
            return
        }
        state = .starting

        Task { @MainActor [weak self] in
            guard let self else { return }
            let microphone = await self.requestMicrophoneAccess()
            do {
                let url = try Self.makeOutputURL()
                try await self.recorder.start(
                    target: ScreenRecorder.Target(
                        displayID: target.screen.displayID,
                        scale: target.screen.backingScaleFactor,
                        excludedWindowNumbers: target.excludedWindowNumbers
                    ),
                    frameRate: Self.frameRate,
                    microphone: microphone,
                    outputURL: url
                )
                self.elapsedBeforeSegment = 0
                self.segmentStart = Date()
                self.elapsed = 0
                self.startElapsedTimer()
                self.state = .recording
            } catch {
                self.state = .idle
                self.presentError(error)
            }
        }
    }

    private func streamFailed(_ error: Error) {
        guard state.isCapturing else { return }
        // Keep whatever was captured so far, then explain what happened.
        stopAndSave { [weak self] _ in
            self?.presentError(error)
        }
    }

    /// Microphone audio is captured through ScreenCaptureKit, which needs macOS 15.
    private func requestMicrophoneAccess() async -> Bool {
        guard #available(macOS 15.0, *) else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func ensureScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // Registers the app in the Screen Recording list and shows the system prompt the first time.
        if CGRequestScreenCaptureAccess() { return true }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "Allow Camera Overlay under System Settings → Privacy & Security → Screen & System Audio Recording, then try again. macOS may ask you to quit and reopen the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            CameraPermission.openScreenRecordingSettings()
        }
        return false
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Recording failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func makeOutputURL() throws -> URL {
        let movies = try FileManager.default.url(for: .moviesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = movies.appendingPathComponent("Camera Overlay", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return folder.appendingPathComponent("Recording \(formatter.string(from: Date())).mov")
    }

    // MARK: Elapsed time

    private func currentElapsed() -> TimeInterval {
        elapsedBeforeSegment + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = self.currentElapsed()
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
    }
}
