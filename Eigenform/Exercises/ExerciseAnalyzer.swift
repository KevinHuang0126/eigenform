import Foundation

/// Categories for form faults. The feedback engine throttles audio per category so
/// one recurring fault can't drown out a different, newly appearing one.
enum FaultCategory: String {
    case depth
    case heelLift
    case hipSag
    case hipPike
    case orientation
    case visibility
}

/// Everything an analyzer can tell the rest of the app about a processed frame.
enum FormEvent: Equatable {
    /// A full rep was completed. Carries the new total.
    case repCompleted(count: Int)
    /// A form fault worth an audio cue (throttled downstream).
    case fault(cue: String, category: FaultCategory)
    /// The movement phase changed (drives the HUD label; not spoken).
    case phaseChanged(String)
    /// The user isn't positioned so the exercise can be evaluated yet.
    case setupGuidance(String)
}

/// One state machine per exercise. Analyzers are fed poses from a single serial
/// context (the main actor, via `WorkoutSessionViewModel`) — they are
/// single-threaded by construction and must not be touched from anywhere else.
protocol ExerciseAnalyzer: AnyObject {
    var exercise: Exercise { get }
    var repCount: Int { get }
    /// Short human-readable phase for the HUD, e.g. "Descending".
    var phaseLabel: String { get }
    /// Consume one frame's pose, mutate internal state, report what happened.
    func process(_ pose: BodyPose) -> [FormEvent]
    func reset()
}

/// Joint sets for picking the camera-facing side of the body in sagittal-view
/// exercises. Vision returns garbage for the occluded far side; committing to the
/// higher-confidence side beats averaging the two.
enum BodySide {
    case left
    case right

    static func preferred(for pose: BodyPose,
                          left: [BodyPose.Joint],
                          right: [BodyPose.Joint]) -> BodySide {
        pose.totalConfidence(of: left) >= pose.totalConfidence(of: right) ? .left : .right
    }
}
