import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // NSApplication.delegate is weak; keep ours alive for the app's lifetime.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private let settings = AppSettings.shared
    private let camera = CameraCaptureManager.shared
    private let recording = RecordingController()
    private var overlay: CameraOverlayController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only (also set via LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)

        let overlay = CameraOverlayController(settings: settings, camera: camera, recording: recording)
        self.overlay = overlay

        let menuBar = MenuBarController(
            onShow: { [weak self] in self?.overlay?.show() },
            onHide: { [weak self] in self?.overlay?.hide() },
            onSettings: { [weak self] in self?.showSettings() },
            onTogglePause: { [weak self] in self?.recording.togglePause() },
            onStopRecording: { [weak self] in self?.recording.stopAndSave() },
            isOverlayVisible: { [weak self] in self?.overlay?.isVisible ?? false }
        )
        self.menuBar = menuBar

        recording.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak menuBar] state in menuBar?.recordingStateChanged(state) }
            .store(in: &cancellables)

        overlay.show()
    }

    /// Launching the app again (e.g. from Finder) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting mid-recording saves what has been captured first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recording.state.isCapturing else { return .terminateNow }
        recording.stopAndSave { _ in
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        camera.stop()
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, camera: camera)
        }
        settingsWindow?.present()
    }
}
