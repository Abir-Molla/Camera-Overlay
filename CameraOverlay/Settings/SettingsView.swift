import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Camera Overlay")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.primaryText)
                    Text("A floating webcam bubble for your screen recordings.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(.bottom, 4)

                CameraSettingsView()
                ShapeSettingsView()
                LookSettingsView()
                FramingSettingsView()
                FaceTrackingSettingsView()
            }
            .padding(.horizontal, 24)
            .padding(.top, 40) // room for the transparent title bar
            .padding(.bottom, 24)
        }
        .frame(minWidth: 440, minHeight: 420)
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
