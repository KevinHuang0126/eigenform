import CoreGraphics

/// Pushup, evaluated side-on with the body roughly horizontal.
///
/// Body line: the hip's signed vertical offset from the shoulder–ankle line,
/// normalized by body length. Negative (toward the floor in Vision space) reads as
/// sagging hips; positive as piking. Rep depth: elbow angle below 90° at the bottom
/// OR the shoulder dropping past half its calibrated lockout height above the wrist
/// — the Y-drop path survives the camera angles that compress the 2D elbow angle
/// (same reasoning as the squat's hip-below-knee test). Counted on return to
/// lockout; a rep that never reached depth gets a "go lower" cue instead of a count.
final class PushupAnalyzer: ExerciseAnalyzer {
    let exercise: Exercise = .pushup

    private enum Phase: String {
        case lockout = "Ready"
        case descending = "Descending"
        case ascending = "Push up"
    }

    // Elbow-angle thresholds sit lower than anatomical truth on purpose: an
    // off-perpendicular camera compresses the 2D angle, so demanding a full 160°
    // lockout made reps stick. 15° of hysteresis between lockout and descent.
    static let lockoutElbowAngle: CGFloat = 150
    static let descentElbowAngle: CGFloat = 135
    static let depthElbowAngle: CGFloat = 90
    static let ascentRebound: CGFloat = 15
    /// Depth also registers when shoulder height above the wrist falls to this
    /// fraction of its calibrated lockout value.
    static let depthDropRatio: CGFloat = 0.5
    /// EMA weight of the newest elbow-angle sample (kills single-frame flapping).
    static let elbowSmoothing: CGFloat = 0.5
    /// Hip offset from the body line, as a fraction of shoulder–ankle length.
    static let sagThreshold: CGFloat = -0.08
    static let pikeThreshold: CGFloat = 0.10
    /// Body counts as horizontal when shoulder–ankle rise is under ~30° of run.
    static let horizontalSlopeLimit: CGFloat = 0.6

    private(set) var repCount = 0
    private var phase: Phase = .lockout
    var phaseLabel: String { phase.rawValue }

    private var descentGate = ConsecutiveFrameGate()
    private var ascentGate = ConsecutiveFrameGate()
    private var lockoutGate = ConsecutiveFrameGate()
    private var depthGate = ConsecutiveFrameGate()
    private var sagGate = LatchingFaultGate(fireThreshold: 8, rearmThreshold: 10)
    private var pikeGate = LatchingFaultGate(fireThreshold: 8, rearmThreshold: 10)
    private var positionGate = ConsecutiveFrameGate(threshold: 45)
    private var visibilityGate = ConsecutiveFrameGate(threshold: 30)

    private var depthReached = false
    private var minElbowAngle: CGFloat = .infinity
    private var smoothedElbowAngle: CGFloat?
    private var lockoutShoulderHeight: CGFloat?

    func process(_ pose: BodyPose) -> [FormEvent] {
        var events: [FormEvent] = []

        let side = BodySide.preferred(for: pose,
                                      left: [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle],
                                      right: [.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle])
        let j: (shoulder: BodyPose.Joint, elbow: BodyPose.Joint, wrist: BodyPose.Joint,
                hip: BodyPose.Joint, ankle: BodyPose.Joint) =
            side == .left ? (.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle)
                          : (.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle)

        guard let shoulder = pose.metricPoint(j.shoulder),
              let elbow = pose.metricPoint(j.elbow),
              let wrist = pose.metricPoint(j.wrist),
              let hip = pose.metricPoint(j.hip),
              let ankle = pose.metricPoint(j.ankle),
              let rawShoulder = pose[j.shoulder],
              let rawWrist = pose[j.wrist],
              let rawElbowAngle = BiomechanicsCalculator.angleDegrees(at: elbow, from: shoulder, to: wrist)
        else {
            if visibilityGate.update(true) {
                visibilityGate.reset()
                events.append(.setupGuidance("Move so your whole body is in frame, side-on"))
            }
            return events
        }
        visibilityGate.reset()

        // The body-line math is meaningless unless the trunk is roughly horizontal.
        let run = abs(ankle.x - shoulder.x)
        let rise = abs(ankle.y - shoulder.y)
        guard run > .ulpOfOne, rise / run < Self.horizontalSlopeLimit else {
            if positionGate.update(true) {
                positionGate.reset()
                events.append(.setupGuidance("Get into a pushup position, side-on to the camera"))
            }
            return events
        }
        positionGate.reset()

        let elbowAngle = smoothedElbowAngle.map {
            $0 * (1 - Self.elbowSmoothing) + rawElbowAngle * Self.elbowSmoothing
        } ?? rawElbowAngle
        smoothedElbowAngle = elbowAngle

        // Body-line faults are live in every phase. Latched: one cue per
        // occurrence, re-armed at the rep boundary.
        let bodyLength = BiomechanicsCalculator.distance(shoulder, ankle)
        if bodyLength > .ulpOfOne,
           let offset = BiomechanicsCalculator.verticalOffset(of: hip,
                                                              fromLineThrough: shoulder,
                                                              and: ankle) {
            let relative = offset / bodyLength
            if sagGate.update(relative < Self.sagThreshold) {
                events.append(.fault(cue: "Lift your hips — stop sagging", category: .hipSag))
            }
            if pikeGate.update(relative > Self.pikeThreshold) {
                events.append(.fault(cue: "Lower your hips — keep your body straight", category: .hipPike))
            }
        }

        switch phase {
        case .lockout:
            // Calibrate how high the shoulder rides above the wrist at lockout
            // (raw normalized Y; the wrist is effectively the floor). Chases upward
            // samples fast but downward ones slowly: a shoulder dropping while the
            // phase still reads "lockout" is the descent starting, and must not
            // drag the reference height down with it.
            let height = rawShoulder.y - rawWrist.y
            lockoutShoulderHeight = lockoutShoulderHeight.map {
                let alpha: CGFloat = height > $0 ? 0.1 : 0.02
                return $0 * (1 - alpha) + height * alpha
            } ?? height
            if descentGate.update(elbowAngle < Self.descentElbowAngle) {
                phase = .descending
                depthReached = false
                minElbowAngle = elbowAngle
                events.append(.phaseChanged(phase.rawValue))
            }

        case .descending:
            minElbowAngle = min(minElbowAngle, elbowAngle)
            // Either signal suffices: the elbow angle when the camera is
            // perpendicular, the shoulder Y-drop when perspective compresses it.
            let shoulderDropped = lockoutShoulderHeight.map {
                rawShoulder.y - rawWrist.y <= Self.depthDropRatio * $0
            } ?? false
            if depthGate.update(elbowAngle < Self.depthElbowAngle || shoulderDropped),
               !depthReached {
                depthReached = true
                events.append(.phaseChanged("Depth reached — push up"))
            }
            if ascentGate.update(elbowAngle > minElbowAngle + Self.ascentRebound) {
                phase = .ascending
                events.append(.phaseChanged(phase.rawValue))
            }

        case .ascending:
            if lockoutGate.update(elbowAngle > Self.lockoutElbowAngle) {
                if depthReached {
                    repCount += 1
                    events.append(.repCompleted(count: repCount))
                } else {
                    events.append(.fault(cue: "Go lower — chest toward the floor", category: .depth))
                }
                phase = .lockout
                depthReached = false
                minElbowAngle = .infinity
                resetTransientGates()
                events.append(.phaseChanged(phase.rawValue))
            }
        }

        return events
    }

    private func resetTransientGates() {
        descentGate.reset()
        ascentGate.reset()
        lockoutGate.reset()
        depthGate.reset()
        sagGate.rearm()
        pikeGate.rearm()
    }

    func reset() {
        repCount = 0
        phase = .lockout
        depthReached = false
        minElbowAngle = .infinity
        smoothedElbowAngle = nil
        lockoutShoulderHeight = nil
        resetTransientGates()
        positionGate.reset()
        visibilityGate.reset()
    }
}
