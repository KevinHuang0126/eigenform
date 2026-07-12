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

    let camera = CameraManager()
    let feedback = FeedbackEngine()

    nonisolated private let estimator = PoseEstimator()
    private var analyzer: ExerciseAnalyzer

    init() {
        analyzer = Exercise.bicepCurl.makeAnalyzer()
    }

    func start() {
        feedback.configureAudioSession()
        feedback.logPhase("Eigenform ready — \(selectedExercise.displayName)")
        camera.sampleHandler = { [weak self] sampleBuffer in
            self?.processFrame(sampleBuffer)
        }
        camera.start()
    }

    func stop() {
        camera.stop()
    }

    func resetSession() {
        let current = analyzer
        current.reset()
        repCount = 0
        phaseLabel = current.phaseLabel
        feedback.clear()
        feedback.logPhase("Session reset")
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
            self.feedback.handle(events)
        }
    }
}
