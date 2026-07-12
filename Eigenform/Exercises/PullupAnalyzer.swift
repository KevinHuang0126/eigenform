import CoreGraphics

/// Pullup, evaluated from a coronal (facing) camera view.
///
/// All comparisons happen in Vision normalized space, where the origin is
/// bottom-left and **larger Y means higher in frame**. Vision has no chin landmark,
/// so the head line stands in: the mean of whichever of nose/left-ear/right-ear pass
/// the confidence floor. Ears sit at roughly nose height and stay confident when the
/// head tilts back at the top of the rep — the exact moment the nose alone gets
/// lost. Still slightly conservative vs. the chin, which is the right direction to
/// err for rep quality. Head and wrist heights are EMA-smoothed before any
/// comparison. The rep counts at the top (head clears the wrist line by a margin);
/// the user must return to a dead hang (head well below wrists) before the next rep
/// can arm — that gap is the hysteresis.
final class PullupAnalyzer: ExerciseAnalyzer {
    let exercise: Exercise = .pullup

    private enum Phase: String {
        case waitingForHang = "Hang from the bar"
        case hanging = "Pull up"
        case topReached = "Lower down"
    }

    /// How far (normalized frame heights) the head must sit below the wrists to
    /// count as a dead hang.
    static let hangHeadBelowWrists: CGFloat = 0.10
    /// How far the head must clear the wrist line for the top — a margin so jitter
    /// at the line can't mint reps.
    static let topClearance: CGFloat = 0.02
    /// Wrists must be at least this far above the shoulders for "hanging from a bar"
    /// to be plausible.
    static let wristsAboveShoulders: CGFloat = 0.05
    /// Rising at least this far off the dead hang and returning without reaching the
    /// top reads as a partial rep worth a cue.
    static let partialRepRise: CGFloat = 0.03
    /// One wrist this far (Y) from the other is a misdetection, not a grip — use the
    /// higher-confidence wrist alone instead of the mean.
    static let wristMismatchTolerance: CGFloat = 0.05
    /// EMA weight of the newest head/wrist sample.
    static let heightSmoothing: CGFloat = 0.4

    private(set) var repCount = 0
    private var phase: Phase = .waitingForHang
    var phaseLabel: String { phase.rawValue }

    private var hangGate = ConsecutiveFrameGate()
    private var topGate = ConsecutiveFrameGate()
    private var setupGate = ConsecutiveFrameGate(threshold: 45)
    private var visibilityGate = ConsecutiveFrameGate(threshold: 30)

    private var smoothedHeadY: CGFloat?
    private var smoothedWristY: CGFloat?
    /// Head height when the current hang phase began, and the highest point reached
    /// since — a rise-and-return without a top is a partial rep.
    private var hangHeadY: CGFloat = 0
    private var peakHeadY: CGFloat = 0

    func process(_ pose: BodyPose) -> [FormEvent] {
        var events: [FormEvent] = []

        // Y-only comparisons: aspect correction is a no-op on the y axis, so raw
        // normalized points are fine here.
        let headPoints: [CGFloat] = [.nose, .leftEar, .rightEar].compactMap { pose[$0]?.y }
        guard !headPoints.isEmpty,
              let leftWrist = pose[.leftWrist],
              let rightWrist = pose[.rightWrist],
              let leftShoulder = pose[.leftShoulder],
              let rightShoulder = pose[.rightShoulder]
        else {
            if visibilityGate.update(true) {
                visibilityGate.reset()
                events.append(.setupGuidance("Face the camera so your head and both hands are visible"))
            }
            return events
        }
        visibilityGate.reset()

        let rawHeadY = headPoints.reduce(0, +) / CGFloat(headPoints.count)
        // A wildly split pair means one wrist is misdetected; trust the confident one.
        let rawWristY: CGFloat
        if abs(leftWrist.y - rightWrist.y) > Self.wristMismatchTolerance {
            rawWristY = pose.confidence(of: .leftWrist) >= pose.confidence(of: .rightWrist)
                ? leftWrist.y : rightWrist.y
        } else {
            rawWristY = (leftWrist.y + rightWrist.y) / 2
        }
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2

        // Arms overhead is the precondition for everything else.
        guard rawWristY > shoulderY + Self.wristsAboveShoulders else {
            if setupGate.update(true) {
                setupGate.reset()
                events.append(.setupGuidance("Grab the bar with both hands overhead"))
            }
            phase = .waitingForHang
            hangGate.reset()
            topGate.reset()
            smoothedHeadY = nil
            smoothedWristY = nil
            return events
        }
        setupGate.reset()

        let headY = smoothedHeadY.map {
            $0 * (1 - Self.heightSmoothing) + rawHeadY * Self.heightSmoothing
        } ?? rawHeadY
        smoothedHeadY = headY
        let wristY = smoothedWristY.map {
            $0 * (1 - Self.heightSmoothing) + rawWristY * Self.heightSmoothing
        } ?? rawWristY
        smoothedWristY = wristY

        let isHanging = hangGate.update(headY < wristY - Self.hangHeadBelowWrists)
        let isAtTop = topGate.update(headY > wristY + Self.topClearance)

        switch phase {
        case .waitingForHang:
            if isHanging {
                enterHang(headY: headY)
                events.append(.phaseChanged(phase.rawValue))
            }
        case .hanging:
            peakHeadY = max(peakHeadY, headY)
            if isAtTop {
                repCount += 1
                phase = .topReached
                events.append(.repCompleted(count: repCount))
                events.append(.phaseChanged(phase.rawValue))
            } else if isHanging, peakHeadY >= hangHeadY + Self.partialRepRise {
                // Rose off the hang and came all the way back down without a top.
                events.append(.fault(cue: "Pull higher — chin over the bar", category: .depth))
                hangHeadY = headY
                peakHeadY = headY
            }
        case .topReached:
            if isHanging {
                enterHang(headY: headY)
                events.append(.phaseChanged(phase.rawValue))
            }
        }

        return events
    }

    private func enterHang(headY: CGFloat) {
        phase = .hanging
        hangHeadY = headY
        peakHeadY = headY
    }

    func reset() {
        repCount = 0
        phase = .waitingForHang
        hangGate.reset()
        topGate.reset()
        setupGate.reset()
        visibilityGate.reset()
        smoothedHeadY = nil
        smoothedWristY = nil
        hangHeadY = 0
        peakHeadY = 0
    }
}
