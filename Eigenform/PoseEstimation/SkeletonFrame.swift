import CoreGraphics
import Vision

/// Immutable snapshot of one frame's visible joints, handed from the processing
/// queue to the UI. Points stay in Vision normalized space (bottom-left origin);
/// `SkeletonOverlayView` owns the conversion to screen coordinates.
struct SkeletonFrame {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    let joints: [Joint: CGPoint]
    let imageSize: CGSize
    /// True when the preview is mirrored (front camera), so the overlay flips x to
    /// stay glued to the on-screen body.
    let mirrored: Bool

    /// Bone graph for the stick-figure debug view.
    static let bones: [(Joint, Joint)] = [
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    init(pose: BodyPose, mirrored: Bool) {
        self.joints = pose.visibleJoints
        self.imageSize = pose.imageSize
        self.mirrored = mirrored
    }
}
