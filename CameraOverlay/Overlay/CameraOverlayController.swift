import AppKit
import Combine
import SwiftUI

/// Owns the floating panel, keeps it in sync with settings and the camera,
/// remembers its position and size, and hosts the hover control bar.
final class CameraOverlayController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let camera: CameraCaptureManager
    private let recording: RecordingController
    private let panel: CameraOverlayPanel
    private let overlayView: CameraOverlayView
    private let controlPanel = OverlayControlPanel()
    private let faceTracker = FaceTracker()
    private var cancellables = Set<AnyCancellable>()
    private var lastShape: CameraShape
    private var trackingAttached = false
    private var lastPlaceholderStatus: CameraCaptureManager.Status?
    private var showingCountdown = false

    // Hover state for the control bar.
    private var hoveringBubble = false
    private var hoveringBar = false
    private var barHideWorkItem: DispatchWorkItem?

    // Full screen camera.
    private var isFullScreen = false
    private var frameBeforeFullScreen: NSRect?

    private(set) var isVisible = false

    init(settings: AppSettings, camera: CameraCaptureManager, recording: RecordingController) {
        self.settings = settings
        self.camera = camera
        self.recording = recording
        self.lastShape = settings.shape

        let frame = Self.initialFrame(saved: settings.windowFrame, shape: settings.shape)
        panel = CameraOverlayPanel(contentRect: frame)
        overlayView = CameraOverlayView(session: camera.session)
        super.init()

        overlayView.frame = NSRect(origin: .zero, size: frame.size)
        overlayView.autoresizingMask = [.width, .height]
        panel.contentView = overlayView
        panel.setFrame(frame, display: false)
        panel.delegate = self

        overlayView.onDoubleClick = { [weak self] in
            guard let self else { return }
            if self.isFullScreen { self.exitFullScreen() } else { self.resetSize() }
        }
        overlayView.onHoverChanged = { [weak self] hovering in
            self?.hoveringBubble = hovering
            self?.updateControlBarVisibility()
        }
        faceTracker.onFaceUpdate = { [weak self] point in self?.overlayView.updateFaceTarget(point) }

        wireControlBar()
        bind()
        applySettings()
    }

    // MARK: Show / hide

    func show() {
        isVisible = true
        ensureOnScreen()
        panel.orderFrontRegardless()
        camera.start()
    }

    /// Hides the bubble and releases the camera entirely, so nothing runs in the background.
    /// A recording in progress keeps going; it can be stopped from the menu bar.
    func hide() {
        isVisible = false
        if isFullScreen { exitFullScreen() }
        hideControlBar()
        panel.orderOut(nil)
        overlayView.resetTracking() // stops the 60 Hz smoothing timer
        camera.stop()
    }

    // MARK: Control bar

    private func wireControlBar() {
        let bar = controlPanel.bar
        bar.onHoverChanged = { [weak self] hovering in
            self?.hoveringBar = hovering
            self?.updateControlBarVisibility()
        }
        bar.onFullScreen = { [weak self] in self?.toggleFullScreen() }
        bar.onRecord = { [weak self] in self?.recording.start(withCountdown: false) }
        bar.onCountdown = { [weak self] in self?.recording.start(withCountdown: true) }
        bar.onPause = { [weak self] in self?.recording.togglePause() }
        bar.onStop = { [weak self] in self?.recording.stopAndSave() }
        bar.onCancel = { [weak self] in self?.recording.cancelCountdown() }

        recording.captureTarget = { [weak self] in
            guard let self, let screen = self.panel.screen ?? NSScreen.main else { return nil }
            return RecordingController.CaptureTarget(
                screen: screen,
                excludedWindowNumbers: [self.controlPanel.windowNumber]
            )
        }
    }

    private func updateControlBarVisibility() {
        let pinned: Bool
        switch recording.state {
        case .countingDown, .starting, .saving: pinned = true
        default: pinned = false
        }
        let shouldShow = isVisible && (hoveringBubble || hoveringBar || pinned)

        barHideWorkItem?.cancel()
        barHideWorkItem = nil

        if shouldShow {
            showControlBar()
        } else {
            // Small grace period so moving from the bubble down to the bar doesn't hide it.
            let item = DispatchWorkItem { [weak self] in self?.hideControlBar() }
            barHideWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
        }
    }

    private func showControlBar() {
        refreshControlBar()
        if controlPanel.parent == nil {
            panel.addChildWindow(controlPanel, ordered: .above)
        }
        controlPanel.orderFrontRegardless()
    }

    private func hideControlBar() {
        hoveringBar = false
        if controlPanel.parent != nil {
            panel.removeChildWindow(controlPanel)
        }
        controlPanel.orderOut(nil)
    }

    private func refreshControlBar() {
        controlPanel.bar.update(state: recording.state, elapsed: recording.elapsed, isFullScreen: isFullScreen)
        controlPanel.sizeToFit()
        layoutControlBar()
    }

    /// Centers the bar just below the camera (above it if there is no room; bottom of the screen in full screen).
    private func layoutControlBar() {
        let size = controlPanel.frame.size
        let gap: CGFloat = 8
        var origin: NSPoint

        if isFullScreen {
            let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 24)
        } else {
            let cameraInWindow = overlayView.convert(overlayView.cameraRect, to: nil)
            let cameraOnScreen = panel.convertToScreen(cameraInWindow)
            origin = NSPoint(x: cameraOnScreen.midX - size.width / 2, y: cameraOnScreen.minY - gap - size.height)
            if let screen = panel.screen, origin.y < screen.visibleFrame.minY {
                origin.y = cameraOnScreen.maxY + gap
            }
        }
        controlPanel.setFrameOrigin(origin)
    }

    // MARK: Full screen

    func toggleFullScreen() {
        if isFullScreen { exitFullScreen() } else { enterFullScreen() }
    }

    private func enterFullScreen() {
        guard !isFullScreen, let screen = panel.screen ?? NSScreen.main else { return }
        frameBeforeFullScreen = panel.frame
        isFullScreen = true // set first so the delegate doesn't persist the full-screen frame
        panel.setFrame(screen.frame, display: true)
        applySettings()
        refreshControlBar()
    }

    private func exitFullScreen() {
        guard isFullScreen else { return }
        isFullScreen = false
        if let frame = frameBeforeFullScreen {
            panel.setFrame(frame, display: true)
        }
        frameBeforeFullScreen = nil
        applySettings()
        ensureOnScreen()
        refreshControlBar()
    }

    // MARK: Bindings

    private func bind() {
        // objectWillChange fires before the value is stored; hop to the main queue to read it after.
        // (GCD main runs during slider tracking, unlike RunLoop.main, so the preview updates live.)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        camera.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.cameraStatusChanged(status) }
            .store(in: &cancellables)

        camera.$videoDimensions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in self?.overlayView.videoSize = size }
            .store(in: &cancellables)

        recording.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.recordingStateChanged(state) }
            .store(in: &cancellables)

        recording.$elapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.controlPanel.isVisible else { return }
                self.refreshControlBar()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.ensureOnScreen() }
            .store(in: &cancellables)
    }

    private func applySettings() {
        var style = OverlayStyle()
        style.shape = settings.shape
        style.cornerFraction = CGFloat(settings.cornerRadius)
        style.ringEnabled = settings.ringEnabled
        style.ringWidth = CGFloat(settings.ringWidth)
        style.ringColor = settings.ringColor
        style.shadowEnabled = settings.shadowEnabled
        style.zoom = CGFloat(settings.zoom)
        style.horizontal = CGFloat(settings.horizontalPosition)
        style.vertical = CGFloat(settings.verticalPosition)
        style.mirror = settings.mirror
        style.faceTracking = settings.faceTracking
        style.fullScreen = isFullScreen
        overlayView.style = style

        if settings.shape != lastShape {
            lastShape = settings.shape
            if settings.shape == .circle, !isFullScreen { makeSquare() }
        }

        camera.update(configuration: .init(
            deviceID: settings.cameraDeviceID,
            resolution: settings.resolution,
            frameRate: settings.frameRate.rawValue
        ))

        if trackingAttached != settings.faceTracking {
            trackingAttached = settings.faceTracking
            camera.setFrameDelegate(trackingAttached ? faceTracker : nil)
        }
    }

    private func recordingStateChanged(_ state: RecordingController.State) {
        if case .countingDown(let remaining) = state {
            showCountdown(remaining)
        } else {
            showCountdown(nil)
        }
        if controlPanel.isVisible { refreshControlBar() }
        updateControlBarVisibility()
    }

    private func cameraStatusChanged(_ status: CameraCaptureManager.Status) {
        if status == .running {
            overlayView.configurePreviewConnection()
        }
        guard status != lastPlaceholderStatus else { return }
        lastPlaceholderStatus = status
        guard !showingCountdown else { return } // the countdown owns the placeholder for now

        switch status {
        case .idle, .starting, .running:
            overlayView.setPlaceholder(nil)
        case .permissionPending:
            showPlaceholder("Waiting for camera permission…", settingsButton: false)
        case .permissionDenied:
            showPlaceholder("Camera access is required.", settingsButton: true)
        case .noCamera:
            showPlaceholder("No camera found.", settingsButton: false)
        case .failed(let message):
            showPlaceholder(message, settingsButton: false)
        }
    }

    private func showPlaceholder(_ message: String, settingsButton: Bool) {
        let view = NSHostingView(rootView: OverlayPlaceholderView(message: message, showsSettingsButton: settingsButton))
        overlayView.setPlaceholder(view, action: settingsButton ? { CameraPermission.openSystemSettings() } : nil)
    }

    /// Shows the countdown digit over the camera; passing nil restores the normal status placeholder.
    private func showCountdown(_ seconds: Int?) {
        if let seconds {
            showingCountdown = true
            overlayView.setPlaceholder(NSHostingView(rootView: CountdownBadgeView(seconds: seconds)))
        } else if showingCountdown {
            showingCountdown = false
            lastPlaceholderStatus = nil
            cameraStatusChanged(camera.status)
        }
    }

    // MARK: Geometry

    private static func cameraContentSize(for shape: CameraShape) -> NSSize {
        shape == .circle ? NSSize(width: 240, height: 240) : NSSize(width: 320, height: 180)
    }

    private static func windowSize(for shape: CameraShape) -> NSSize {
        let content = cameraContentSize(for: shape)
        let margin = CameraOverlayView.shadowMargin * 2
        return NSSize(width: content.width + margin, height: content.height + margin)
    }

    private static func initialFrame(saved: NSRect?, shape: CameraShape) -> NSRect {
        let minSide = CameraOverlayView.minimumCameraSide + CameraOverlayView.shadowMargin * 2
        if let saved,
           saved.width >= minSide, saved.height >= minSide,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
            return saved
        }
        return defaultFrame(shape: shape)
    }

    /// Bottom-right corner of the main screen.
    private static func defaultFrame(shape: CameraShape) -> NSRect {
        let size = windowSize(for: shape)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: visible.maxX - size.width - 24, y: visible.minY + 24, width: size.width, height: size.height)
    }

    private func resetSize() {
        let size = Self.windowSize(for: settings.shape)
        let old = panel.frame
        let frame = NSRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2, width: size.width, height: size.height)
        panel.setFrame(frame, display: true, animate: true)
    }

    private func makeSquare() {
        let old = panel.frame
        let side = min(old.width, old.height)
        panel.setFrame(NSRect(x: old.midX - side / 2, y: old.midY - side / 2, width: side, height: side), display: true)
    }

    private func ensureOnScreen() {
        guard !isFullScreen else { return }
        let frame = panel.frame
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            panel.setFrame(Self.defaultFrame(shape: settings.shape), display: true)
        }
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        if !isFullScreen { settings.windowFrame = panel.frame }
        if controlPanel.isVisible { layoutControlBar() }
    }

    func windowDidResize(_ notification: Notification) {
        if !isFullScreen { settings.windowFrame = panel.frame }
        if controlPanel.isVisible { layoutControlBar() }
    }
}
