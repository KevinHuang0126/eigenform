import Foundation

enum Exercise: String, CaseIterable, Identifiable {
    case bicepCurl
    case squat
    case pushup
    case pullup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bicepCurl: return "Curl"
        case .squat: return "Squat"
        case .pushup: return "Pushup"
        case .pullup: return "Pullup"
        }
    }

    func makeAnalyzer() -> ExerciseAnalyzer {
        switch self {
        case .bicepCurl: return CurlAnalyzer()
        case .squat: return SquatAnalyzer()
        case .pushup: return PushupAnalyzer()
        case .pullup: return PullupAnalyzer()
        }
    }
}
