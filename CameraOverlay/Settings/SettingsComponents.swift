import SwiftUI

enum Theme {
    static let background = Color(red: 0.086, green: 0.102, blue: 0.110)
    static let card = Color(red: 0.125, green: 0.149, blue: 0.157)
    static let cardBorder = Color.white.opacity(0.07)
    static let field = Color.white.opacity(0.05)
    static let accent = Color(red: 0.27, green: 0.85, blue: 0.79)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.5)
}

/// Rounded card with an accent icon and a bold title.
struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.primaryText)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }
}

/// Monospaced value readout shown next to a slider title.
struct ValueBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.25)))
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.primaryText)
                Spacer()
                ValueBadge(text: format(value))
            }
            Slider(value: $value, in: range)
                .tint(Theme.accent)
                .controlSize(.small)
        }
    }
}

struct PickerRow<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder var options: () -> Options

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Theme.primaryText)
            Spacer(minLength: 12)
            Picker("", selection: $selection, content: options)
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 230)
        }
    }
}

/// Teal checkbox that matches the dark card style.
struct AccentCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(configuration.isOn ? Theme.accent : Theme.field)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(configuration.isOn ? Color.clear : Color.white.opacity(0.18), lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(Theme.background)
                    }
                }
                .frame(width: 18, height: 18)

                configuration.label
                    .font(.system(size: 13))
                    .foregroundColor(Theme.primaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CaptionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
