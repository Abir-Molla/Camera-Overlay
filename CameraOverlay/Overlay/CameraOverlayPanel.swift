import AppKit

/// Borderless, transparent, always-on-top panel that never steals focus from the app
/// you are recording, follows you across Spaces, and stays capturable by OBS.
final class CameraOverlayPanel: NSPanel {
    convenience init(contentRect: NSRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the shadow is drawn by the view so it follows the shape
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .readOnly // visible to screen capture (OBS)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
