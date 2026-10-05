import SwiftUI

struct FaceTrackingSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsCard("Face Tracking", systemImage: "person.crop.square") {
            Toggle("Keep my face centered", isOn: $settings.faceTracking)
                .toggleStyle(AccentCheckboxStyle())

            CaptionText("Runs on your Mac with Apple's Vision framework. Adds a slight zoom so the frame has room to follow you.")
        }
    }
}
