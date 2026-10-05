import SwiftUI

struct CameraSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var camera: CameraCaptureManager

    var body: some View {
        SettingsCard("Camera", systemImage: "video") {
            if camera.status == .permissionDenied {
                PermissionBanner()
            }

            PickerRow(title: "Camera Device", selection: deviceSelection) {
                if camera.devices.isEmpty {
                    Text("No camera found").tag("")
                }
                ForEach(camera.devices) { device in
                    Text(device.name).tag(device.id)
                }
            }

            PickerRow(title: "Resolution", selection: $settings.resolution) {
                ForEach(CameraResolution.allCases) { resolution in
                    Text(resolution.rawValue).tag(resolution)
                }
            }

            PickerRow(title: "Frame Rate", selection: $settings.frameRate) {
                ForEach(CameraFrameRate.allCases) { rate in
                    Text(label(for: rate)).tag(rate)
                }
            }
        }
    }

    private func label(for rate: CameraFrameRate) -> String {
        if rate == .fps60 && !camera.selectedDeviceSupports60fps {
            return "60 fps (not supported, uses 30)"
        }
        return rate.label
    }

    /// Shows the saved camera, or the one actually in use if the saved one is unplugged.
    private var deviceSelection: Binding<String> {
        Binding(
            get: {
                let devices = camera.devices
                if let id = settings.cameraDeviceID, devices.contains(where: { $0.id == id }) {
                    return id
                }
                if let active = camera.activeDeviceID, devices.contains(where: { $0.id == active }) {
                    return active
                }
                return devices.first?.id ?? ""
            },
            set: { newValue in
                settings.cameraDeviceID = newValue.isEmpty ? nil : newValue
            }
        )
    }
}

struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Camera access is required.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.primaryText)
            Spacer()
            Button("Open Camera Settings") {
                CameraPermission.openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}
