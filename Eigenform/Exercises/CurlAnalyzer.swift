import CoreGraphics

/// Bicep curl — the desk-testable sandbox movement.
///
/// Tracks the elbow angle (shoulder–elbow–wrist) of whichever arm Vision sees more
/// confidently. A rep arms at full extension (θ > 160°) and counts at full flexion
/// (θ < 45°); the arm must re-extend before the next rep can count. The wide gap
/// between the two thresholds is deliberate hysteresis.
final class CurlAnalyzer: ExerciseAnalyzer {
    let exercise: Exercise = .bicepCurl

    private enum Phase: String {
        case waitingForExtension = "Extend your arm"
        case extended = "Curl up"
        case flexed = "Lower down"
    }

    static let extensionThreshold: CGFloat = 160
    static let flexionThreshold: CGFloat = 45

    private(set) var repCount = 0
    private var phase: Phase = .waitingForExtension
    var phaseLabel: String { phase.rawValue }

    private var extensionGate = ConsecutiveFrameGate()
    private var flexionGate = ConsecutiveFrameGate()
    // A full second of missing arm before we nag, so brief occlusions stay silent.
    private var visibilityGate = ConsecutiveFrameGate(threshold: 30)

    func process(_ pose: BodyPose) -> [FormEvent] {
        let side = BodySide.preferred(for: pose,
                                      left: [.leftShoulder, .leftElbow, .leftWrist],
                                      right: [.rightShoulder, .rightElbow, .rightWrist])
        let joints: (BodyPose.Joint, BodyPose.Joint, BodyPose.Joint) =
            side == .left ? (.leftShoulder, .leftElbow, .leftWrist)
                          : (.rightShoulder, .rightElbow, .rightWrist)

        guard let shoulder = pose.metricPoint(joints.0),
              let elbow = pose.metricPoint(joints.1),
              let wrist = pose.metricPoint(joints.2),
              let angle = BiomechanicsCalculator.angleDegrees(at: elbow, from: shoulder, to: wrist)
        else {
            if visibilityGate.update(true) {
                visibilityGate.reset()
                return [.setupGuidance("Make sure your whole arm is in frame")]
            }
            return []
        }
        visibilityGate.reset()

        var events: [FormEvent] = []
        let isExtended = extensionGate.update(angle > Self.extensionThreshold)
        let isFlexed = flexionGate.update(angle < Self.flexionThreshold)

        switch phase {
        case .waitingForExtension:
            if isExtended {
                phase = .extended
                events.append(.phaseChanged(phase.rawValue))
            }
        case .extended:
            if isFlexed {
                repCount += 1
                phase = .flexed
                events.append(.repCompleted(count: repCount))
                events.append(.phaseChanged(phase.rawValue))
            }
        case .flexed:
            if isExtended {
                phase = .extended
                events.append(.phaseChanged(phase.rawValue))
            }
        }
        return events
    }

    func reset() {
        repCount = 0
        phase = .waitingForExtension
        extensionGate.reset()
        flexionGate.reset()
        visibilityGate.reset()
    }
}
