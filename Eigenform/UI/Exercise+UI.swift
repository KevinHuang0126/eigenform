import SwiftUI

/// UI-side metadata for each exercise. Lives apart from `Exercise.swift` so the
/// logic layer stays Foundation-only and keeps compiling in `Tests/run_tests.sh`.
extension Exercise {
    /// One-line camera setup hint, mirrored from the analyzers' guidance cues.
    var setupHint: String {
        switch self {
        case .bicepCurl: return "Face the camera, whole arm in frame"
        case .squat: return "Stand side-on to the camera"
        case .pushup: return "Side-on, whole body in frame"
        case .pullup: return "Face the camera, head and hands visible"
        }
    }
}
