import AVFoundation
import Vision

/// Wraps `VNDetectHumanBodyPoseRequest`. Called on the camera's video output queue;
/// the request object is reused across frames, which Vision expects.
///
/// `@unchecked Sendable`: the reused request is mutable state, but every call site
/// lives on the camera's single serial output queue.
final class PoseEstimator: @unchecked Sendable {
    private let request = VNDetectHumanBodyPoseRequest()

    /// Runs pose detection on one frame. Returns nil when no body is found or the
    /// buffer is unreadable. Buffers arrive gravity-upright — the capture connection's
    /// rotation is device-tracked (see `CameraManager`), so a person the right way up
    /// in the world is the right way up in the buffer regardless of how the phone is
    /// held; orientation is therefore always `.up`.
    func estimatePose(in sampleBuffer: CMSampleBuffer) -> BodyPose? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer))

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return BodyPose(observation: observation, imageSize: imageSize)
    }
}
