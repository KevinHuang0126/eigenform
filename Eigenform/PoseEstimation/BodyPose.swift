import CoreGraphics
import Vision

/// A single frame's body pose.
///
/// All stored locations are in **Vision normalized space**: x and y in 0...1 with the
/// origin at the **bottom-left** of the frame. Every downstream rule in the exercise
/// analyzers is written against this space; conversion to UIKit/SwiftUI top-left
/// coordinates happens only at the rendering edge (see `SkeletonOverlayView`).
struct BodyPose {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    /// Joints below this confidence are treated as missing rather than fed into the
    /// math — occluded limbs otherwise produce wild angle jitter.
    static let minimumConfidence: Float = 0.3

    private let joints: [Joint: (location: CGPoint, confidence: Float)]

    /// Pixel dimensions of the source buffer this pose was detected in.
    let imageSize: CGSize

    /// Width / height of the source buffer. Normalized coordinates are relative to
    /// each axis independently, so angle math on raw normalized points is distorted
    /// on non-square frames; `metricPoint(_:)` corrects for this.
    var aspectRatio: CGFloat { imageSize.width / imageSize.height }

    init?(observation: VNHumanBodyPoseObservation, imageSize: CGSize) {
        guard let recognized = try? observation.recognizedPoints(.all), !recognized.isEmpty else {
            return nil
        }
        var joints: [Joint: (location: CGPoint, confidence: Float)] = [:]
        for (name, point) in recognized {
            joints[name] = (point.location, point.confidence)
        }
        self.joints = joints
        self.imageSize = imageSize
    }

    /// Direct construction from synthetic data, used by the logic test harness.
    init(joints: [Joint: (location: CGPoint, confidence: Float)], imageSize: CGSize) {
        self.joints = joints
        self.imageSize = imageSize
    }

    /// Normalized Vision-space location, or nil when the joint is missing or below
    /// the confidence floor.
    subscript(joint: Joint) -> CGPoint? {
        guard let entry = joints[joint], entry.confidence >= Self.minimumConfidence else {
            return nil
        }
        return entry.location
    }

    func confidence(of joint: Joint) -> Float {
        joints[joint]?.confidence ?? 0
    }

    /// Location scaled so x and y share the same physical unit (frame heights).
    /// Use this space for any angle or distance calculation.
    func metricPoint(_ joint: Joint) -> CGPoint? {
        guard let p = self[joint] else { return nil }
        return CGPoint(x: p.x * aspectRatio, y: p.y)
    }

    /// Sum of confidences over a joint set — used to pick the camera-facing side
    /// of the body for sagittal-view exercises.
    func totalConfidence(of set: [Joint]) -> Float {
        set.reduce(0) { $0 + confidence(of: $1) }
    }

    /// All joints that pass the confidence floor, for skeleton rendering.
    var visibleJoints: [Joint: CGPoint] {
        joints.compactMapValues { entry in
            entry.confidence >= Self.minimumConfidence ? entry.location : nil
        }
    }
}
