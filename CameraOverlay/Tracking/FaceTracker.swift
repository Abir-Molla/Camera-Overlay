import AVFoundation
import QuartzCore
import Vision

/// Detects the largest face in camera frames with Apple's Vision framework (on-device).
/// Only receives frames while face tracking is enabled, and analyses at most ~15 frames/s.
final class FaceTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on the main queue with the face center in normalized image coordinates
    /// (0...1, origin bottom-left, unmirrored), or nil when no face is visible.
    var onFaceUpdate: ((CGPoint?) -> Void)?

    private let minimumInterval: CFTimeInterval = 1.0 / 15.0
    private var lastAnalysis: CFTimeInterval = 0
    private let request = VNDetectFaceRectanglesRequest()
    private let sequenceHandler = VNSequenceRequestHandler()

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastAnalysis >= minimumInterval else { return }
        lastAnalysis = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            return
        }

        let faces = request.results ?? []
        let largest = faces.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }
        let center = largest.map { CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY) }

        DispatchQueue.main.async { [weak self] in
            self?.onFaceUpdate?(center)
        }
    }
}
