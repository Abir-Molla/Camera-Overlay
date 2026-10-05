import AppKit
import SwiftUI

enum CameraResolution: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .p720: return CGSize(width: 1280, height: 720)
        case .p1080: return CGSize(width: 1920, height: 1080)
        }
    }
}

enum CameraFrameRate: Int, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue) fps" }
}

/// Every user setting, persisted to UserDefaults as soon as it changes.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultRingColor = NSColor(srgbRed: 0.27, green: 0.85, blue: 0.79, alpha: 1)

    private enum Key {
        static let cameraDeviceID = "camera.deviceID"
        static let resolution = "camera.resolution"
        static let frameRate = "camera.frameRate"
        static let shape = "shape.kind"
        static let cornerRadius = "shape.cornerRadius"
        static let ringEnabled = "look.ringEnabled"
        static let ringWidth = "look.ringWidth"
        static let ringColor = "look.ringColor"
        static let shadowEnabled = "look.shadowEnabled"
        static let zoom = "framing.zoom"
        static let horizontalPosition = "framing.horizontal"
        static let verticalPosition = "framing.vertical"
        static let mirror = "framing.mirror"
        static let faceTracking = "tracking.enabled"
        static let windowFrame = "window.frame"
    }

    private let defaults: UserDefaults

    // MARK: Camera

    @Published var cameraDeviceID: String? {
        didSet { defaults.set(cameraDeviceID, forKey: Key.cameraDeviceID) }
    }
    @Published var resolution: CameraResolution {
        didSet { defaults.set(resolution.rawValue, forKey: Key.resolution) }
    }
    @Published var frameRate: CameraFrameRate {
        didSet { defaults.set(frameRate.rawValue, forKey: Key.frameRate) }
    }

    // MARK: Shape

    @Published var shape: CameraShape {
        didSet { defaults.set(shape.rawValue, forKey: Key.shape) }
    }
    /// Corner radius as a fraction of the shorter side, so it scales with the window.
    @Published var cornerRadius: Double {
        didSet { defaults.set(cornerRadius, forKey: Key.cornerRadius) }
    }

    // MARK: Look

    @Published var ringEnabled: Bool {
        didSet { defaults.set(ringEnabled, forKey: Key.ringEnabled) }
    }
    @Published var ringWidth: Double {
        didSet { defaults.set(ringWidth, forKey: Key.ringWidth) }
    }
    @Published var ringColor: NSColor {
        didSet { defaults.set(Self.components(of: ringColor), forKey: Key.ringColor) }
    }
    @Published var shadowEnabled: Bool {
        didSet { defaults.set(shadowEnabled, forKey: Key.shadowEnabled) }
    }

    // MARK: Framing

    @Published var zoom: Double {
        didSet { defaults.set(zoom, forKey: Key.zoom) }
    }
    /// -1 (left edge of the image) ... 1 (right edge).
    @Published var horizontalPosition: Double {
        didSet { defaults.set(horizontalPosition, forKey: Key.horizontalPosition) }
    }
    /// -1 (bottom edge of the image) ... 1 (top edge).
    @Published var verticalPosition: Double {
        didSet { defaults.set(verticalPosition, forKey: Key.verticalPosition) }
    }
    @Published var mirror: Bool {
        didSet { defaults.set(mirror, forKey: Key.mirror) }
    }

    // MARK: Face tracking

    @Published var faceTracking: Bool {
        didSet { defaults.set(faceTracking, forKey: Key.faceTracking) }
    }

    // MARK: Window (not @Published: it changes on every drag event)

    var windowFrame: NSRect? {
        get {
            guard let string = defaults.string(forKey: Key.windowFrame) else { return nil }
            let rect = NSRectFromString(string)
            return rect.isEmpty ? nil : rect
        }
        set {
            if let newValue {
                defaults.set(NSStringFromRect(newValue), forKey: Key.windowFrame)
            } else {
                defaults.removeObject(forKey: Key.windowFrame)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cameraDeviceID = defaults.string(forKey: Key.cameraDeviceID)
        resolution = CameraResolution(rawValue: defaults.string(forKey: Key.resolution) ?? "") ?? .p1080
        frameRate = CameraFrameRate(rawValue: defaults.integer(forKey: Key.frameRate)) ?? .fps30
        shape = CameraShape(rawValue: defaults.string(forKey: Key.shape) ?? "") ?? .circle
        cornerRadius = Self.double(defaults, Key.cornerRadius, default: 0.18)
        ringEnabled = Self.bool(defaults, Key.ringEnabled, default: true)
        ringWidth = Self.double(defaults, Key.ringWidth, default: 3)
        ringColor = Self.color(from: defaults.array(forKey: Key.ringColor) as? [Double])
        shadowEnabled = Self.bool(defaults, Key.shadowEnabled, default: true)
        zoom = Self.double(defaults, Key.zoom, default: 1)
        horizontalPosition = Self.double(defaults, Key.horizontalPosition, default: 0)
        verticalPosition = Self.double(defaults, Key.verticalPosition, default: 0)
        mirror = Self.bool(defaults, Key.mirror, default: true)
        faceTracking = Self.bool(defaults, Key.faceTracking, default: false)
    }

    /// SwiftUI `ColorPicker` binding for the ring color.
    var ringColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: self.ringColor) },
            set: { self.ringColor = NSColor($0) }
        )
    }

    // MARK: Helpers

    private static func bool(_ defaults: UserDefaults, _ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    private static func double(_ defaults: UserDefaults, _ key: String, default value: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? value
    }

    private static func components(of color: NSColor) -> [Double] {
        let rgb = color.usingColorSpace(.sRGB) ?? defaultRingColor
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent].map { Double($0) }
    }

    private static func color(from components: [Double]?) -> NSColor {
        guard let c = components, c.count == 4 else { return defaultRingColor }
        return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
    }
}
