import AppKit

/// The menu bar icon and its menu.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let showItem: NSMenuItem
    private let hideItem: NSMenuItem
    private let launchItem: NSMenuItem
    private let pauseRecordingItem: NSMenuItem
    private let stopRecordingItem: NSMenuItem
    private let recordingSeparator = NSMenuItem.separator()

    private let onShow: () -> Void
    private let onHide: () -> Void
    private let onSettings: () -> Void
    private let onTogglePause: () -> Void
    private let onStopRecording: () -> Void
    private let isOverlayVisible: () -> Bool

    init(
        onShow: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        isOverlayVisible: @escaping () -> Bool
    ) {
        self.onShow = onShow
        self.onHide = onHide
        self.onSettings = onSettings
        self.onTogglePause = onTogglePause
        self.onStopRecording = onStopRecording
        self.isOverlayVisible = isOverlayVisible

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        showItem = NSMenuItem(title: "Show Camera", action: #selector(MenuBarController.showCamera), keyEquivalent: "")
        hideItem = NSMenuItem(title: "Hide Camera", action: #selector(MenuBarController.hideCamera), keyEquivalent: "")
        launchItem = NSMenuItem(title: "Launch at Login", action: #selector(MenuBarController.toggleLaunchAtLogin), keyEquivalent: "")
        pauseRecordingItem = NSMenuItem(title: "Pause Recording", action: #selector(MenuBarController.togglePause), keyEquivalent: "")
        stopRecordingItem = NSMenuItem(title: "Stop Recording & Save", action: #selector(MenuBarController.stopRecording), keyEquivalent: "")

        super.init()

        statusItem.button?.toolTip = "Camera Overlay"
        updateIcon(recording: false)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(MenuBarController.openSettings), keyEquivalent: ",")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp

        for item in [showItem, hideItem, settingsItem, launchItem, pauseRecordingItem, stopRecordingItem] {
            item.target = self
        }

        let header = NSMenuItem(title: "Camera Overlay", action: nil, keyEquivalent: "")
        header.isEnabled = false

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(showItem)
        menu.addItem(hideItem)
        menu.addItem(settingsItem)
        // Recording controls: only shown while a recording is in progress (reachable even if the bubble is hidden).
        menu.addItem(recordingSeparator)
        menu.addItem(pauseRecordingItem)
        menu.addItem(stopRecordingItem)
        menu.addItem(.separator())
        menu.addItem(launchItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        recordingStateChanged(.idle)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let visible = isOverlayVisible()
        showItem.isEnabled = !visible
        hideItem.isEnabled = visible
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    func recordingStateChanged(_ state: RecordingController.State) {
        let capturing = state.isCapturing
        recordingSeparator.isHidden = !capturing
        pauseRecordingItem.isHidden = !capturing
        stopRecordingItem.isHidden = !capturing
        pauseRecordingItem.title = state == .paused ? "Resume Recording" : "Pause Recording"
        updateIcon(recording: capturing)
    }

    private func updateIcon(recording: Bool) {
        guard let button = statusItem.button else { return }
        if recording {
            let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = false
            button.image = image
            button.toolTip = "Camera Overlay — Recording"
        } else {
            let image = NSImage(systemSymbolName: "web.camera", accessibilityDescription: "Camera Overlay")
                ?? NSImage(systemSymbolName: "video", accessibilityDescription: "Camera Overlay")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Camera Overlay"
        }
    }

    @objc private func showCamera() { onShow() }
    @objc private func hideCamera() { onHide() }
    @objc private func openSettings() { onSettings() }
    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.toggle() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func stopRecording() { onStopRecording() }
}
