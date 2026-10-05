import SwiftUI

struct ShapeSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsCard("Shape", systemImage: "circle.dashed") {
            HStack(spacing: 10) {
                ForEach(CameraShape.allCases) { shape in
                    ShapeTile(shape: shape, isSelected: settings.shape == shape) {
                        settings.shape = shape
                    }
                }
            }

            if settings.shape == .roundedRectangle {
                SliderRow(
                    title: "Corner Radius",
                    value: $settings.cornerRadius,
                    range: 0.02...0.45,
                    format: { "\(Int(($0 * 100).rounded()))%" }
                )
            }
        }
    }
}

private struct ShapeTile: View {
    let shape: CameraShape
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                CameraShapeGlyph(shape: shape)
                    .stroke(isSelected ? Theme.accent : Theme.primaryText.opacity(0.75), lineWidth: 1.6)
                    .frame(width: shape == .circle ? 26 : 36, height: 26)
                Text(shape.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? Theme.accent : Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.14) : Theme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
