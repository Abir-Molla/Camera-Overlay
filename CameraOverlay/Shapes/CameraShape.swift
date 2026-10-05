import AppKit
import SwiftUI

/// The three supported camera shapes. All of them are rendered by Core Animation
/// (a clipping layer with a corner radius), which is GPU-cheap and anti-aliased.
enum CameraShape: String, CaseIterable, Identifiable {
    case circle
    case roundedRectangle
    case rectangle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: return "Circle"
        case .roundedRectangle: return "Rounded"
        case .rectangle: return "Rectangle"
        }
    }

    /// The rect the camera occupies inside `rect`. A circle is always a centered square.
    func frame(in rect: CGRect) -> CGRect {
        guard self == .circle else { return rect }
        let side = min(rect.width, rect.height)
        return CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
    }

    /// Corner radius in points. `fraction` is relative to the shorter side (rounded rectangle only).
    func cornerRadius(for size: CGSize, fraction: CGFloat) -> CGFloat {
        let side = min(size.width, size.height)
        switch self {
        case .circle: return side / 2
        case .roundedRectangle: return max(0, min(side * fraction, side / 2))
        case .rectangle: return 0
        }
    }

    /// Outline used for the drop shadow.
    func path(in rect: CGRect, fraction: CGFloat) -> CGPath {
        switch self {
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .roundedRectangle:
            let limit = max(0, min(rect.width, rect.height) / 2 - 0.01)
            let radius = min(cornerRadius(for: rect.size, fraction: fraction), limit)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }
}

/// Small outline glyph for the shape picker in Settings.
struct CameraShapeGlyph: Shape {
    let shape: CameraShape

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .circle:
            let side = min(rect.width, rect.height)
            return Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        case .roundedRectangle:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.3, style: .continuous)
        case .rectangle:
            return Path(rect)
        }
    }
}
