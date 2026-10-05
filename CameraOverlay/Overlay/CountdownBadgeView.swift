import SwiftUI

/// Big countdown digit shown over the camera before a recording starts.
struct CountdownBadgeView: View {
    let seconds: Int

    var body: some View {
        Text("\(seconds)")
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.white)
            .frame(width: 96, height: 96)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .environment(\.colorScheme, .dark)
    }
}
