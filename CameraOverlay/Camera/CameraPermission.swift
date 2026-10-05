import AppKit

enum CameraPermission {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
    private static let screenRecordingURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Opens System Settings → Privacy & Security → Camera.
    static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// Opens System Settings → Privacy & Security → Screen & System Audio Recording.
    static func openScreenRecordingSettings() {
        NSWorkspace.shared.open(screenRecordingURL)
    }
}
