import CoreGraphics

/// Squat, evaluated from a sagittal (side-on) camera view.
///
/// Depth uses the hip-below-knee test (hip Y ≤ knee Y in Vision space) rather than a
/// raw knee-angle threshold — it matches the "femur parallel" standard across body
/// proportions and is immune to 2D angle distortion. The knee angle still drives the
/// phase transitions (standing / descending / ascending).
///
/// Heel lift: Vision has no heel or toe landmarks (ADR amendment 001), so the ankle's
/// standing height is calibrated while the user stands and a mid-rep rise beyond a
/// tolerance triggers the cue.
final class SquatAnalyzer: ExerciseAnalyzer {
    let exercise: Exercise = .squat

    private enum Phase: String {
        case standing = "Standing"
        case descending = "Descending"
        case ascending = "Ascending"
    }

    static let standingKneeAngle: CGFloat = 160
    static let descentKneeAngle: CGFloat = 150
    /// Knee-angle rebound off the rep's minimum that flips descent to ascent.
    static let ascentRebound: CGFloat = 15
    /// Heel-lift tolerance scales with the user's apparent size: this fraction of
    /// the calibrated shank height (knee-to-ankle), floored so a distant user isn't
    /// judged against pure detector noise.
    static let heelLiftShankFraction: CGFloat = 0.2
    static let heelLiftMinTolerance: CGFloat = 0.03
    /// Standing frames the baselines must see before the heel check goes live.
    static let heelCalibrationFrames = 15
    /// Ankle confidence below which the heel check is skipped — the ankle keypoint
    /// drifts exactly when the knee is deeply flexed.
    static let heelConfidenceFloor: Float = 0.5
    /// Shoulder separation (metric units) beyond which the user is facing the camera.
    static let facingCameraShoulderGap: CGFloat = 0.15

    private(set) var repCount = 0
    private var phase: Phase = .standing
    var phaseLabel: String { phase.rawValue }

    private var descentGate = ConsecutiveFrameGate()
    private var ascentGate = ConsecutiveFrameGate()
    private var lockoutGate = ConsecutiveFrameGate()
    private var depthGate = ConsecutiveFrameGate()
    private var heelGate = LatchingFaultGate(fireThreshold: 5, rearmThreshold: 10)
    private var orientationGate = ConsecutiveFrameGate(threshold: 45)
    private var visibilityGate = ConsecutiveFrameGate(threshold: 30)

    private var depthReached = false
    private var minKneeAngle: CGFloat = .infinity
    private var ankleBaselineY: CGFloat?
    private var shankHeight: CGFloat?
    private var calibrationFrames = 0

    func process(_ pose: BodyPose) -> [FormEvent] {
        var events: [FormEvent] = []

        // Orientation: a sagittal read needs the user side-on. Only nag while standing.
        if phase == .standing,
           let ls = pose.metricPoint(.leftShoulder),
           let rs = pose.metricPoint(.rightShoulder),
           orientationGate.update(abs(ls.x - rs.x) > Self.facingCameraShoulderGap) {
            orientationGate.reset()
            return [.setupGuidance("Turn sideways to the camera")]
        }

        let side = BodySide.preferred(for: pose,
                                      left: [.leftHip, .leftKnee, .leftAnkle],
                                      right: [.rightHip, .rightKnee, .rightAnkle])
        let joints: (hip: BodyPose.Joint, knee: BodyPose.Joint, ankle: BodyPose.Joint) =
            side == .left ? (.leftHip, .leftKnee, .leftAnkle)
                          : (.rightHip, .rightKnee, .rightAnkle)

        guard let hipMetric = pose.metricPoint(joints.hip),
              let kneeMetric = pose.metricPoint(joints.knee),
              let ankleMetric = pose.metricPoint(joints.ankle),
              let hip = pose[joints.hip],
              let knee = pose[joints.knee],
              let ankle = pose[joints.ankle],
              let kneeAngle = BiomechanicsCalculator.angleDegrees(at: kneeMetric,
                                                                  from: hipMetric,
                                                                  to: ankleMetric)
        else {
            if visibilityGate.update(true) {
                visibilityGate.reset()
                events.append(.setupGuidance("Step back so your hips, knees and ankles are in frame"))
            }
            return events
        }
        visibilityGate.reset()

        switch phase {
        case .standing:
            // Calibrate the ankle's standing height and the shank length (EMAs
            // smooth detector noise). Y-only, so raw normalized points are fine.
            // The baseline chases downward samples fast but upward ones slowly: an
            // ankle rising while nominally "standing" is the very lift being
            // detected, and must not recalibrate the floor out from under the check.
            ankleBaselineY = ankleBaselineY.map {
                let alpha: CGFloat = ankle.y < $0 ? 0.1 : 0.02
                return $0 * (1 - alpha) + ankle.y * alpha
            } ?? ankle.y
            let shank = knee.y - ankle.y
            shankHeight = shankHeight.map { $0 * 0.9 + shank * 0.1 } ?? shank
            calibrationFrames += 1
            if descentGate.update(kneeAngle < Self.descentKneeAngle) {
                phase = .descending
                depthReached = false
                minKneeAngle = kneeAngle
                events.append(.phaseChanged(phase.rawValue))
            }

        case .descending:
            minKneeAngle = min(minKneeAngle, kneeAngle)
            if depthGate.update(hip.y <= knee.y), !depthReached {
                depthReached = true
                events.append(.phaseChanged("Depth reached — drive up"))
            }
            if ascentGate.update(kneeAngle > minKneeAngle + Self.ascentRebound) {
                phase = .ascending
                events.append(.phaseChanged(phase.rawValue))
            }

        case .ascending:
            if lockoutGate.update(kneeAngle > Self.standingKneeAngle) {
                if depthReached {
                    repCount += 1
                    events.append(.repCompleted(count: repCount))
                } else {
                    events.append(.fault(cue: "Squat deeper — hips below knees", category: .depth))
                }
                phase = .standing
                depthReached = false
                minKneeAngle = .infinity
                resetTransientGates()
                events.append(.phaseChanged(phase.rawValue))
            }
        }

        // Heel lift is checked mid-rep only, needs a properly calibrated standing
        // baseline, and skips low-confidence ankle frames. Latched: one cue per
        // occurrence, re-armed at the rep boundary.
        if phase != .standing, let baseline = ankleBaselineY, let shank = shankHeight,
           calibrationFrames >= Self.heelCalibrationFrames,
           pose.confidence(of: joints.ankle) >= Self.heelConfidenceFloor {
            let tolerance = max(Self.heelLiftMinTolerance, Self.heelLiftShankFraction * shank)
            if heelGate.update(ankle.y > baseline + tolerance) {
                events.append(.fault(cue: "Keep your heels down", category: .heelLift))
            }
        }

        return events
    }

    private func resetTransientGates() {
        descentGate.reset()
        ascentGate.reset()
        lockoutGate.reset()
        depthGate.reset()
        heelGate.rearm()
    }

    func reset() {
        repCount = 0
        phase = .standing
        depthReached = false
        minKneeAngle = .infinity
        ankleBaselineY = nil
        shankHeight = nil
        calibrationFrames = 0
        resetTransientGates()
        orientationGate.reset()
        visibilityGate.reset()
    }
}
