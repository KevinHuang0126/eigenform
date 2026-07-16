import AVFoundation
import Combine
import SwiftUI

/// Glue between the pipeline stages: camera frames → pose estimation → the active
/// exercise's state machine → feedback + UI state.
///
/// Threading: Vision inference (the expensive part) runs on the camera's video
/// output queue; the resulting pose hops to the main actor, where the state-machine
/// analysis (trivial math) and all publishing happen. The analyzer is therefore
/// only ever touched on the main actor — exercise switching needs no extra
/// synchronization. The camera queue is serial, so poses arrive in order.
@MainActor
final class WorkoutSessionViewModel: ObservableObject {
    @Published var selectedExercise: Exercise = .bicepCurl {
        didSet { switchExercise(to: selectedExercise) }
    }
    @Published private(set) var repCount = 0
    @Published private(set) var phaseLabel = ""
    @Published private(set) var skeleton: SkeletonFrame?
    /// Monotonic counter bumped once per fault event; views key haptics and the
    /// skeleton's coral flash off it (the fault text itself lives in the transcript).
    @Published private(set) var faultPulse = 0
    private(set) var sessionStart = Date()

    let camera = CameraManager()
    let feedback = FeedbackEngine()

    nonisolated private let estimator = PoseEstimator()
    private var analyzer: ExerciseAnalyzer

    init() {
        analyzer = Exercise.bicepCurl.makeAnalyzer()
    }

    func start() {
        sessionStart = Date()
        // Keep the screen awake while the camera is watching a set; re-enabled in stop().
        UIApplication.shared.isIdleTimerDisabled = true
        feedback.configureAudioSession()
        feedback.logPhase("EigenForm ready — \(selectedExercise.displayName)")
        camera.sampleHandler = { [weak self] sampleBuffer in
            self?.processFrame(sampleBuffer)
        }
        camera.start()
    }

    func stop() {
        camera.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func resetSession() {
        let current = analyzer
        current.reset()
        repCount = 0
        phaseLabel = current.phaseLabel
        sessionStart = Date()
        feedback.clear()
        feedback.logPhase("Session reset")
    }

    /// Snapshot of the set that just ended, for the summary screen. Fault lines
    /// are re-grouped from the transcript because coalescing only merges
    /// consecutive repeats of the same cue.
    func makeSummary() -> SessionSummary {
        var faultCounts: [String: Int] = [:]
        var order: [String] = []
        for entry in feedback.transcript where entry.kind == .fault {
            if faultCounts[entry.text] == nil { order.append(entry.text) }
            faultCounts[entry.text, default: 0] += entry.count
        }
        return SessionSummary(
            exercise: selectedExercise,
            reps: repCount,
            duration: Date().timeIntervalSince(sessionStart),
            faults: order.map { (text: $0, count: faultCounts[$0] ?? 0) })
    }

    private func switchExercise(to exercise: Exercise) {
        let fresh = exercise.makeAnalyzer()
        analyzer = fresh
        repCount = 0
        phaseLabel = fresh.phaseLabel
        feedback.logPhase("Switched to \(exercise.displayName)")
    }

    /// Runs on the camera's video output queue.
    nonisolated private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pose = estimator.estimatePose(in: sampleBuffer) else {
            Task { @MainActor [weak self] in self?.skeleton = nil }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let frame = SkeletonFrame(pose: pose, mirrored: self.camera.position == .front)
            let events = self.analyzer.process(pose)
            self.skeleton = frame
            self.repCount = self.analyzer.repCount
            self.phaseLabel = self.analyzer.phaseLabel
            if events.contains(where: { if case .fault = $0 { return true } else { return false } }) {
                self.faultPulse += 1
            }
            self.feedback.handle(events)
        }
    }
}

/// What a finished set looked like; consumed by `SummaryView`.
struct SessionSummary {
    let exercise: Exercise
    let reps: Int
    let duration: TimeInterval
    let faults: [(text: String, count: Int)]
}
