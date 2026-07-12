import AVFoundation
import Foundation

/// The AVFoundation edge of the feedback pipeline: speaks what the `CueArbiter`
/// decides to surface and republishes its transcript for SwiftUI. All cadence
/// policy (cooldowns, escalation, coalescing) lives in the arbiter — see ADR-003.
/// Main-actor: every mutation drives SwiftUI, and speech APIs are cheap enough to
/// call from the main thread.
///
/// The audio session ducks other audio, so cues cut through gym music instead of
/// killing it. No microphone is requested anywhere; input isn't needed.
@MainActor
final class FeedbackEngine: ObservableObject {
    @Published private(set) var transcript: [TranscriptEntry] = []

    private let synthesizer = AVSpeechSynthesizer()
    private let arbiter = CueArbiter()

    func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? audioSession.setActive(true)
    }

    func handle(_ events: [FormEvent]) {
        let toSpeak = arbiter.handle(events, at: Date())
        transcript = arbiter.transcript
        toSpeak.forEach(speakNow)
    }

    func logPhase(_ text: String) {
        arbiter.logInfo(text, at: Date())
        transcript = arbiter.transcript
    }

    func clear() {
        arbiter.clear()
        transcript = arbiter.transcript
    }

    private func speakNow(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
