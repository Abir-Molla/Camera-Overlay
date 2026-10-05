import SwiftUI

struct FramingSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsCard("Framing", systemImage: "crop") {
            SliderRow(
                title: "Zoom",
                value: $settings.zoom,
                range: 1...3,
                format: { String(format: "%.2f×", $0) }
            )

            VStack(alignment: .leading, spacing: 16) {
                SliderRow(
                    title: "Horizontal Position",
                    value: $settings.horizontalPosition,
                    range: -1...1,
                    format: { String(format: "%+.2f", $0) }
                )
                SliderRow(
                    title: "Vertical Position",
                    value: $settings.verticalPosition,
                    range: -1...1,
                    format: { String(format: "%+.2f", $0) }
                )
            }
            .disabled(settings.faceTracking)
            .opacity(settings.faceTracking ? 0.4 : 1)

            if settings.faceTracking {
                CaptionText("Face tracking is positioning the camera.")
            }

            Toggle("Mirror", isOn: $settings.mirror)
                .toggleStyle(AccentCheckboxStyle())
        }
    }
}
