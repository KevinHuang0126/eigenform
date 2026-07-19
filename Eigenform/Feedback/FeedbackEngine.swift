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
    /// Best speech voice installed on this device (nil = system default). Resolved
    /// once per engine; a session restart picks up voices downloaded meanwhile.
    private let voice = FeedbackEngine.bestAvailableVoice()

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
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    /// The highest-quality voice installed for the device language: premium beats
    /// enhanced beats compact, and an exact locale match breaks ties. Returns nil
    /// when only compact (robotic) voices are installed, so the system default
    /// applies unchanged — Apple's premium/enhanced voices are free but arrive via
    /// Settings → Accessibility → Spoken Content → Voices, and this picks them up
    /// automatically once downloaded. Novelty voices (Bells, Boing…) are excluded.
    private static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let locale = AVSpeechSynthesisVoice.currentLanguageCode()
        let language = locale.split(separator: "-").first.map(String.init) ?? locale

        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { lhs, rhs in
                (lhs.quality.rawValue, lhs.language == locale ? 1 : 0)
                    < (rhs.quality.rawValue, rhs.language == locale ? 1 : 0)
            }

        guard let best, best.quality != .default else { return nil }
        return best
    }
}
