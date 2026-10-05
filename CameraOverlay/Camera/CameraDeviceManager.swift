import AVFoundation
import CoreMedia

struct CameraDeviceInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Device discovery and format selection. Stateless and safe to call from any queue.
enum CameraDeviceManager {
    static func makeDiscoverySession() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .unspecified)
    }

    private static var deviceTypes: [AVCaptureDevice.DeviceType] {
        if #available(macOS 14.0, *) {
            return [.builtInWideAngleCamera, .external, .continuityCamera]
        } else {
            return [.builtInWideAngleCamera, .externalUnknown]
        }
    }

    static func uniqueDevices(_ devices: [AVCaptureDevice]) -> [AVCaptureDevice] {
        var seen = Set<String>()
        return devices.filter { seen.insert($0.uniqueID).inserted }
    }

    static func availableDevices() -> [AVCaptureDevice] {
        uniqueDevices(makeDiscoverySession().devices)
    }

    /// The saved camera if it is connected, otherwise the built-in camera, otherwise anything.
    static func resolveDevice(preferredID: String?) -> AVCaptureDevice? {
        if let id = preferredID, let device = AVCaptureDevice(uniqueID: id), device.isConnected {
            return device
        }
        let devices = availableDevices()
        return devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? devices.first
            ?? AVCaptureDevice.default(for: .video)
    }

    static func dimensions(of format: AVCaptureDevice.Format) -> CGSize {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return CGSize(width: CGFloat(d.width), height: CGFloat(d.height))
    }

    /// A frame duration inside one of the format's supported ranges, or nil if the
    /// format can't reach `frameRate`. Clamped so AVFoundation never throws.
    static func frameDuration(for format: AVCaptureDevice.Format, frameRate: Int) -> CMTime? {
        let target = Double(frameRate)
        guard let range = format.videoSupportedFrameRateRanges.first(where: {
            $0.maxFrameRate >= target - 0.5 && $0.minFrameRate <= target + 0.5
        }) else { return nil }

        let desired = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        if CMTimeCompare(desired, range.minFrameDuration) < 0 { return range.minFrameDuration }
        if CMTimeCompare(desired, range.maxFrameDuration) > 0 { return range.maxFrameDuration }
        return desired
    }

    static func supports(_ format: AVCaptureDevice.Format, frameRate: Int) -> Bool {
        frameDuration(for: format, frameRate: frameRate) != nil
    }

    /// Picks the format closest to the requested resolution, preferring one that
    /// supports the requested frame rate, then 30 fps.
    static func bestFormat(for device: AVCaptureDevice, resolution: CameraResolution, frameRate: Int) -> AVCaptureDevice.Format? {
        let formats = device.formats
        guard !formats.isEmpty else { return nil }

        let target = resolution.size
        func distance(_ format: AVCaptureDevice.Format) -> CGFloat {
            let size = dimensions(of: format)
            return abs(size.height - target.height) + abs(size.width - target.width) * 0.5
        }

        let best = formats.map(distance).min() ?? 0
        let candidates = formats.filter { distance($0) == best }
        return candidates.first(where: { supports($0, frameRate: frameRate) })
            ?? candidates.first(where: { supports($0, frameRate: 30) })
            ?? candidates.first
    }
}
