import SwiftUI

struct LookSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsCard("Look", systemImage: "circle.circle") {
            Toggle("Enable Ring", isOn: $settings.ringEnabled)
                .toggleStyle(AccentCheckboxStyle())

            if settings.ringEnabled {
                SliderRow(
                    title: "Ring Width",
                    value: $settings.ringWidth,
                    range: 1...12,
                    format: { "\(Int($0.rounded())) pt" }
                )

                HStack {
                    Text("Ring Color")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.primaryText)
                    Spacer()
                    ColorPicker("Ring Color", selection: settings.ringColorBinding, supportsOpacity: false)
                        .labelsHidden()
                }
            }

            Divider().overlay(Theme.cardBorder)

            Toggle("Enable Shadow", isOn: $settings.shadowEnabled)
                .toggleStyle(AccentCheckboxStyle())
        }
    }
}
