import AVFoundation
import Combine
import CoreMedia

/// Owns the single AVCaptureSession. Public API is used from the main thread;
/// all session work happens on a private serial queue.
final class CameraCaptureManager: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case starting
        case running
        case permissionPending
        case permissionDenied
        case noCamera
        case failed(String)
    }

    struct Configuration: Equatable {
        var deviceID: String?
        var resolution: CameraResolution
        var frameRate: Int
    }

    static let shared = CameraCaptureManager()

    @Published private(set) var devices: [CameraDeviceInfo] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var activeDeviceID: String?
    @Published private(set) var videoDimensions = CGSize(width: 1920, height: 1080)
    @Published private(set) var selectedDeviceSupports60fps = false

    let session = AVCaptureSession()

    /// True between `start()` and `stop()`.
    private(set) var wantsRunning = false

    private let sessionQueue = DispatchQueue(label: "CameraOverlay.session")
    private let frameQueue = DispatchQueue(label: "CameraOverlay.frames", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let discovery = CameraDeviceManager.makeDiscoverySession()
    private var discoveryObservation: NSKeyValueObservation?
    private var runtimeErrorObserver: NSObjectProtocol?

    private var configuration = Configuration(deviceID: nil, resolution: .p1080, frameRate: 30)
    private weak var frameDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?

    // Session-queue only.
    private var currentInput: AVCaptureDeviceInput?

    private override init() {
        super.init()

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]

        // Cameras plugged in / unplugged (USB webcams, Continuity Camera).
        discoveryObservation = discovery.observe(\.devices, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.devicesChanged() }
        }

        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("AVCaptureSessionRuntimeErrorNotification"),
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.handleRuntimeError()
        }

        refreshDevices()
    }

    // MARK: Public API (main thread)

    func refreshDevices() {
        devices = CameraDeviceManager.uniqueDevices(discovery.devices).map {
            CameraDeviceInfo(id: $0.uniqueID, name: $0.localizedName)
        }
        updateCapabilities()
    }

    func update(configuration newValue: Configuration) {
        guard newValue != configuration else { return }
        configuration = newValue
        updateCapabilities()
        if wantsRunning { applyOnSessionQueue() }
    }

    /// Attaches a frame consumer (face tracking). Pass nil to stop delivering frames entirely.
    func setFrameDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?) {
        frameDelegate = delegate
        if wantsRunning { applyOnSessionQueue() }
    }

    func start() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            applyOnSessionQueue()
        case .notDetermined:
            status = .permissionPending
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted else {
                        self.status = .permissionDenied
                        return
                    }
                    self.refreshDevices()
                    if self.wantsRunning { self.applyOnSessionQueue() }
                }
            }
        default:
            status = .permissionDenied
        }
    }

    /// Stops the session and removes the input so the camera is fully released.
    func stop() {
        wantsRunning = false
        if status == .running || status == .starting { status = .idle }
        sessionQueue.async { [weak self] in
            self?.tearDownSession()
        }
    }

    // MARK: Private (main thread)

    private func devicesChanged() {
        refreshDevices()
        if wantsRunning, AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            applyOnSessionQueue()
        }
    }

    private func handleRuntimeError() {
        guard wantsRunning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.wantsRunning else { return }
            self.applyOnSessionQueue()
        }
    }

    private func applyOnSessionQueue() {
        let config = configuration
        let delegate = frameDelegate
        if status != .running { status = .starting }
        sessionQueue.async { [weak self] in
            self?.applyConfiguration(config, frameDelegate: delegate)
        }
    }

    private func updateCapabilities() {
        guard let device = CameraDeviceManager.resolveDevice(preferredID: configuration.deviceID),
              let format = CameraDeviceManager.bestFormat(for: device, resolution: configuration.resolution, frameRate: 60)
        else {
            selectedDeviceSupports60fps = false
            return
        }
        selectedDeviceSupports60fps = CameraDeviceManager.supports(format, frameRate: 60)
    }

    private func publish(_ newStatus: Status, deviceID: String? = nil, dimensions: CGSize? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // A late result from before stop() must not flip the state back to running.
            guard self.wantsRunning else { return }
            self.status = newStatus
            if let deviceID { self.activeDeviceID = deviceID }
            if let dimensions, dimensions.width > 0, dimensions.height > 0, dimensions != self.videoDimensions {
                self.videoDimensions = dimensions
            }
        }
    }

    // MARK: Session queue

    private func applyConfiguration(_ config: Configuration, frameDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?) {
        guard let device = CameraDeviceManager.resolveDevice(preferredID: config.deviceID) else {
            tearDownSession()
            publish(.noCamera)
            return
        }

        session.beginConfiguration()

        if let input = currentInput, input.device.uniqueID != device.uniqueID || !input.device.isConnected {
            session.removeInput(input)
            currentInput = nil
        }

        if currentInput == nil {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    publish(.failed("This camera can't be used right now."))
                    return
                }
                session.addInput(input)
                currentInput = input
            } catch {
                session.commitConfiguration()
                publish(.failed("Couldn't open \(device.localizedName)."))
                return
            }
        }

        // Frames are only delivered (and only cost CPU) while face tracking is on.
        let hasOutput = session.outputs.contains(videoOutput)
        if let frameDelegate {
            if !hasOutput, session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            videoOutput.setSampleBufferDelegate(frameDelegate, queue: frameQueue)
            if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        } else {
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            if hasOutput { session.removeOutput(videoOutput) }
        }

        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
        }

        // Applied after the session is running so the session preset can't override it.
        let dimensions = applyFormat(to: device, config: config)

        if session.isRunning {
            publish(.running, deviceID: device.uniqueID, dimensions: dimensions)
        } else {
            publish(.failed("The camera didn't start."), deviceID: device.uniqueID)
        }
    }

    private func applyFormat(to device: AVCaptureDevice, config: Configuration) -> CGSize {
        guard let format = CameraDeviceManager.bestFormat(for: device, resolution: config.resolution, frameRate: config.frameRate) else {
            return CameraDeviceManager.dimensions(of: device.activeFormat)
        }
        do {
            try device.lockForConfiguration()
            if device.activeFormat != format {
                device.activeFormat = format
            }
            let rate = CameraDeviceManager.supports(format, frameRate: config.frameRate) ? config.frameRate : 30
            if let duration = CameraDeviceManager.frameDuration(for: format, frameRate: rate) {
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
            device.unlockForConfiguration()
        } catch {
            NSLog("CameraOverlay: could not configure \(device.localizedName): \(error.localizedDescription)")
        }
        return CameraDeviceManager.dimensions(of: device.activeFormat)
    }

    private func tearDownSession() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        if session.outputs.contains(videoOutput) {
            session.removeOutput(videoOutput)
        }
        session.commitConfiguration()
        currentInput = nil
    }
}
