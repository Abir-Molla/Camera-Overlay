import AppKit
import AVFoundation
import QuartzCore

/// Everything the overlay needs to draw itself.
struct OverlayStyle: Equatable {
    var shape: CameraShape = .circle
    var cornerFraction: CGFloat = 0.18
    var ringEnabled = true
    var ringWidth: CGFloat = 3
    var ringColor: NSColor = AppSettings.defaultRingColor
    var shadowEnabled = true
    var zoom: CGFloat = 1
    var horizontal: CGFloat = 0
    var vertical: CGFloat = 0
    var mirror = true
    var faceTracking = false
    /// Camera fills the whole window edge to edge: no shape, ring, shadow, drag or resize.
    var fullScreen = false
}

/// The camera bubble: a GPU-composited preview layer clipped to the selected shape,
/// with an optional ring and soft shadow. Also handles dragging and edge resizing.
final class CameraOverlayView: NSView {
    /// Transparent room around the camera so the shadow isn't cut off.
    static let shadowMargin: CGFloat = 16
    static let minimumCameraSide: CGFloat = 90
    static let maximumCameraSide: CGFloat = 1400
    /// Face tracking needs a little zoom so there is image to pan into.
    static let trackingMinimumZoom: CGFloat = 1.25

    private struct ResizeEdges: OptionSet {
        let rawValue: Int
        static let left = ResizeEdges(rawValue: 1 << 0)
        static let right = ResizeEdges(rawValue: 1 << 1)
        static let top = ResizeEdges(rawValue: 1 << 2)
        static let bottom = ResizeEdges(rawValue: 1 << 3)
    }

    private struct ResizeSession {
        let edges: ResizeEdges
        let startFrame: NSRect
        let startMouse: NSPoint
    }

    let previewLayer: AVCaptureVideoPreviewLayer
    private let shadowLayer = CALayer()
    private let clipLayer = CALayer()
    private var placeholderView: NSView?
    private var placeholderContent: NSView?
    private var placeholderAction: (() -> Void)?

    var style = OverlayStyle() {
        didSet {
            guard style != oldValue else { return }
            if !style.faceTracking { resetTracking() }
            layoutCameraLayers()
        }
    }

    /// Pixel size of the camera's active format (used for aspect-fill math).
    var videoSize = CGSize(width: 1920, height: 1080) {
        didSet { layoutCameraLayers() }
    }

    var onDoubleClick: (() -> Void)?
    /// Mouse entered (true) or left (false) the bubble.
    var onHoverChanged: ((Bool) -> Void)?

    // Face tracking state: normalized, unmirrored image coordinates, origin bottom-left.
    private var faceTarget: CGPoint?
    private var faceCurrent: CGPoint?
    private var smoothingTimer: Timer?

    private var resizeSession: ResizeSession?
    private var mouseTrackingArea: NSTrackingArea?

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: NSRect(x: 0, y: 0, width: 272, height: 272))

        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor

        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowRadius = 10
        shadowLayer.shadowOffset = CGSize(width: 0, height: -4)
        shadowLayer.shadowOpacity = 0

        clipLayer.masksToBounds = true
        clipLayer.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = NSColor.clear.cgColor

        clipLayer.addSublayer(previewLayer)
        layer?.addSublayer(shadowLayer)
        layer?.addSublayer(clipLayer)

        layoutCameraLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        smoothingTimer?.invalidate()
    }

    // MARK: Layout

    /// The rect the camera bubble occupies (shape-aware), inside the shadow margin.
    var cameraRect: CGRect {
        if style.fullScreen { return bounds }
        let inner = bounds.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin)
        return style.shape.frame(in: inner)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutCameraLayers()
    }

    func layoutCameraLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let rect = cameraRect
        guard rect.width > 1, rect.height > 1 else { return }

        clipLayer.frame = rect
        clipLayer.cornerRadius = style.fullScreen ? 0 : style.shape.cornerRadius(for: rect.size, fraction: style.cornerFraction)
        clipLayer.cornerCurve = style.shape == .roundedRectangle ? .continuous : .circular
        clipLayer.borderWidth = style.ringEnabled && !style.fullScreen ? style.ringWidth : 0
        clipLayer.borderColor = style.ringColor.cgColor

        shadowLayer.frame = bounds
        shadowLayer.shadowPath = style.shape.path(in: rect, fraction: style.cornerFraction)
        shadowLayer.shadowOpacity = style.shadowEnabled && !style.fullScreen ? 0.35 : 0

        layoutPreview(in: rect.size)
        layoutPlaceholder(in: rect)
    }

    /// Aspect-fills the video into the bubble, then applies zoom, position and mirroring.
    /// Offsets are clamped so the image always covers the whole shape.
    private func layoutPreview(in size: CGSize) {
        let video = CGSize(width: max(videoSize.width, 1), height: max(videoSize.height, 1))
        let zoom = style.faceTracking ? max(style.zoom, Self.trackingMinimumZoom) : max(style.zoom, 1)
        let fill = max(size.width / video.width, size.height / video.height) * zoom
        let content = CGSize(width: video.width * fill, height: video.height * fill)

        let maxX = max(0, (content.width - size.width) / 2)
        let maxY = max(0, (content.height - size.height) / 2)
        // Layer y grows upward unless an ancestor flips geometry.
        let ySign: CGFloat = clipLayer.contentsAreFlipped() ? -1 : 1

        var offset: CGPoint
        if style.faceTracking, let face = faceCurrent {
            let mirrorSign: CGFloat = style.mirror ? -1 : 1
            offset = CGPoint(
                x: -(face.x - 0.5) * content.width * mirrorSign,
                y: -(face.y - 0.5) * content.height * ySign
            )
        } else {
            offset = CGPoint(x: -style.horizontal * maxX, y: -style.vertical * maxY * ySign)
        }
        offset.x = min(max(offset.x, -maxX), maxX)
        offset.y = min(max(offset.y, -maxY), maxY)

        previewLayer.bounds = CGRect(origin: .zero, size: content)
        previewLayer.position = CGPoint(x: size.width / 2 + offset.x, y: size.height / 2 + offset.y)
        previewLayer.transform = style.mirror ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }

    // MARK: Placeholder

    /// Shows `content` centered in the bubble. Clicking it runs `action`; it never blocks dragging.
    func setPlaceholder(_ content: NSView?, action: (() -> Void)? = nil) {
        placeholderView?.removeFromSuperview()
        placeholderView = nil
        placeholderContent = nil
        placeholderAction = action
        if let content {
            let container = PassthroughView()
            content.autoresizingMask = [.width, .height]
            container.addSubview(content)
            addSubview(container)
            placeholderView = container
            placeholderContent = content
        }
        layoutCameraLayers()
    }

    private func layoutPlaceholder(in rect: CGRect) {
        guard let container = placeholderView, let content = placeholderContent else { return }
        let available = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
        let fitting = content.fittingSize
        let size = CGSize(width: min(fitting.width, available.width), height: min(fitting.height, available.height))
        container.frame = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        content.frame = container.bounds
    }

    /// Keep the preview unmirrored at the connection level; mirroring is done with a
    /// layer transform so face-tracking math always works on the raw image.
    func configurePreviewConnection() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = false
    }

    // MARK: Face tracking smoothing

    func updateFaceTarget(_ point: CGPoint?) {
        guard style.faceTracking, let point else { return } // no face: hold the last framing
        if let target = faceTarget, hypot(point.x - target.x, point.y - target.y) < 0.015 {
            return // dead zone: ignore detector jitter
        }
        faceTarget = point
        if faceCurrent == nil {
            faceCurrent = point
            layoutCameraLayers()
        }
        startSmoothing()
    }

    func resetTracking() {
        stopSmoothing()
        faceTarget = nil
        faceCurrent = nil
    }

    private func startSmoothing() {
        guard smoothingTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.smoothingStep()
        }
        RunLoop.main.add(timer, forMode: .common)
        smoothingTimer = timer
    }

    private func stopSmoothing() {
        smoothingTimer?.invalidate()
        smoothingTimer = nil
    }

    private func smoothingStep() {
        guard let target = faceTarget, var current = faceCurrent else {
            stopSmoothing()
            return
        }
        // Exponential ease toward the target (~0.2 s time constant at 60 Hz).
        let factor: CGFloat = 0.08
        current.x += (target.x - current.x) * factor
        current.y += (target.y - current.y) * factor
        if hypot(target.x - current.x, target.y - current.y) < 0.0005 {
            current = target
            stopSmoothing()
        }
        faceCurrent = current
        layoutCameraLayers()
    }

    // MARK: Mouse: drag to move, edges to resize, double-click to reset

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTrackingArea { removeTrackingArea(mouseTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        mouseTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        resizeCursor(for: resizeEdges(at: point)).set()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        if resizeSession == nil { NSCursor.arrow.set() }
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            resizeSession = nil
            onDoubleClick?()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let action = placeholderAction, let container = placeholderView, container.frame.contains(point) {
            action()
            return
        }
        if style.fullScreen { return } // nothing to drag or resize
        if let edges = resizeEdges(at: point), let window {
            resizeSession = ResizeSession(edges: edges, startFrame: window.frame, startMouse: NSEvent.mouseLocation)
        } else {
            resizeSession = nil
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session = resizeSession, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - session.startMouse.x
        let dy = mouse.y - session.startMouse.y
        let start = session.startFrame
        let edges = session.edges

        var width = start.width
        var height = start.height
        if edges.contains(.left) { width -= dx } else if edges.contains(.right) { width += dx }
        if edges.contains(.bottom) { height -= dy } else if edges.contains(.top) { height += dy }

        if style.shape == .circle {
            let horizontal = edges.contains(.left) || edges.contains(.right)
            let vertical = edges.contains(.top) || edges.contains(.bottom)
            let side: CGFloat
            if horizontal && vertical {
                side = max(width, height)
            } else if horizontal {
                side = width
            } else {
                side = height
            }
            width = side
            height = side
        }

        let margin = Self.shadowMargin * 2
        let minSide = Self.minimumCameraSide + margin
        let maxSide = Self.maximumCameraSide + margin
        width = min(max(width, minSide), maxSide)
        height = min(max(height, minSide), maxSide)

        var frame = NSRect(x: start.minX, y: start.minY, width: width, height: height)
        if edges.contains(.left) {
            frame.origin.x = start.maxX - width
        } else if !edges.contains(.right) {
            frame.origin.x = start.midX - width / 2
        }
        if edges.contains(.bottom) {
            frame.origin.y = start.maxY - height
        } else if !edges.contains(.top) {
            frame.origin.y = start.midY - height / 2
        }
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        resizeSession = nil
    }

    private func resizeEdges(at point: CGPoint) -> ResizeEdges? {
        guard !style.fullScreen else { return nil }
        let rect = cameraRect
        let band: CGFloat = 12
        guard rect.insetBy(dx: -4, dy: -4).contains(point) else { return nil }

        var edges: ResizeEdges = []
        if style.shape == .circle {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = hypot(dx, dy)
            guard distance >= radius - band, distance <= radius + 4, distance > 0 else { return nil }
            let nx = dx / distance
            let ny = dy / distance
            if nx < -0.38 { edges.insert(.left) } else if nx > 0.38 { edges.insert(.right) }
            if ny < -0.38 { edges.insert(.bottom) } else if ny > 0.38 { edges.insert(.top) }
        } else {
            if point.x - rect.minX < band { edges.insert(.left) } else if rect.maxX - point.x < band { edges.insert(.right) }
            if point.y - rect.minY < band { edges.insert(.bottom) } else if rect.maxY - point.y < band { edges.insert(.top) }
        }
        return edges.isEmpty ? nil : edges
    }

    private func resizeCursor(for edges: ResizeEdges?) -> NSCursor {
        guard let edges else { return .arrow }
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)
        switch (horizontal, vertical) {
        case (true, false): return .resizeLeftRight
        case (false, true): return .resizeUpDown
        default: return .crosshair
        }
    }
}
