import AppKit
import SwiftUI

/// Shown inside the bubble when there is no live feed (permission, no camera, error).
struct OverlayPlaceholderView: View {
    let message: String
    let showsSettingsButton: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showsSettingsButton {
                Button("Open Camera Settings") {
                    CameraPermission.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: 200)
        .environment(\.colorScheme, .dark)
    }
}

/// Container that never receives mouse events itself, so clicks and drags reach the
/// overlay view underneath (which handles the placeholder's button action).
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
