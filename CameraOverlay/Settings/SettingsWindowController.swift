import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings, camera: CameraCaptureManager) {
        let root = SettingsView()
            .environmentObject(settings)
            .environmentObject(camera)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.086, green: 0.102, blue: 0.110, alpha: 1)
        window.contentView = NSHostingView(rootView: root)
        window.contentMinSize = NSSize(width: 440, height: 420)
        window.isReleasedWhenClosed = false
        // Keep Settings above other apps' windows (the app is menu-bar only, so it would
        // otherwise drop behind whatever you click next). Opens in the current Space.
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.setFrameAutosaveName("CameraOverlaySettings")

        self.init(window: window)
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
