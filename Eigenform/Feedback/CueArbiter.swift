import Foundation

struct TranscriptEntry: Identifiable, Equatable {
    enum Kind {
        case rep
        case fault
        case guidance
        case info
    }

    let id = UUID()
    var date: Date
    let text: String
    let kind: Kind
    /// Consecutive repeats coalesced into this row (rendered as "cue ×N").
    var count: Int = 1
}

/// Owns every decision about when a cue is surfaced — speech cadence and the
/// transcript alike. Analyzers emit one fault event per occurrence (see
/// `LatchingFaultGate`); this class governs repetition *across* occurrences so a
/// recurring fault backs off instead of nagging on a fixed beat (ADR-003).
///
/// Time is injected through `handle(_:at:)` and the class is Foundation-only, so it
/// compiles in the native logic-test build where the AVFoundation-bound
/// `FeedbackEngine` cannot.
final class CueArbiter {
    /// Minimum gap before a cue key speaks again.
    static let baseCooldown: TimeInterval = 6
    /// Each repeat speak multiplies the key's cooldown, up to `maxCooldown`.
    static let cooldownGrowth: Double = 2
    static let maxCooldown: TimeInterval = 24
    /// A key silent this long starts over at `baseCooldown`.
    static let escalationForget: TimeInterval = 30
    /// Hard cap on speaks per key inside any rolling `spokenWindow`.
    static let maxSpokenPerWindow = 3
    static let spokenWindow: TimeInterval = 60
    /// Repeats of the last transcript row inside this window bump ×N instead of
    /// appending — the transcript stays honest without scrolling spam.
    static let coalesceWindow: TimeInterval = 10
    private static let maxTranscriptEntries = 200

    private(set) var transcript: [TranscriptEntry] = []

    private var cooldownByKey: [String: TimeInterval] = [:]
    private var lastSpokenByKey: [String: Date] = [:]
    private var spokenTimesByKey: [String: [Date]] = [:]

    /// Consumes one frame's events; returns the texts that should be spoken now.
    func handle(_ events: [FormEvent], at now: Date) -> [String] {
        var toSpeak: [String] = []
        for event in events {
            switch event {
            case .repCompleted(let count):
                // Rep counts always speak — instant count feedback is the core
                // training loop (ADR-002).
                append("Rep \(count)", kind: .rep, at: now)
                toSpeak.append("\(count)")
            case .fault(let cue, let category):
                if shouldSpeak(key: "fault.\(category.rawValue)", at: now) {
                    toSpeak.append(cue)
                }
                coalesce(cue, kind: .fault, at: now)
            case .setupGuidance(let text):
                // Keyed by text so "turn sideways" and "step back" don't throttle
                // each other.
                if shouldSpeak(key: text, at: now) {
                    toSpeak.append(text)
                }
                coalesce(text, kind: .guidance, at: now)
            case .phaseChanged(let label):
                logInfo(label, at: now)
            }
        }
        return toSpeak
    }

    func logInfo(_ text: String, at now: Date) {
        // Phase events fire on transitions, so an identical back-to-back row is
        // noise, not information.
        if let last = transcript.last, last.kind == .info, last.text == text {
            return
        }
        append(text, kind: .info, at: now)
    }

    func clear() {
        transcript.removeAll()
        cooldownByKey.removeAll()
        lastSpokenByKey.removeAll()
        spokenTimesByKey.removeAll()
    }

    private func shouldSpeak(key: String, at now: Date) -> Bool {
        let recent = (spokenTimesByKey[key] ?? []).filter {
            now.timeIntervalSince($0) < Self.spokenWindow
        }
        spokenTimesByKey[key] = recent
        guard recent.count < Self.maxSpokenPerWindow else { return false }

        let current = cooldownByKey[key] ?? Self.baseCooldown
        if let last = lastSpokenByKey[key] {
            let silence = now.timeIntervalSince(last)
            if silence >= Self.escalationForget {
                cooldownByKey[key] = Self.baseCooldown
            } else if silence < current {
                return false
            } else {
                cooldownByKey[key] = min(current * Self.cooldownGrowth, Self.maxCooldown)
            }
        }
        lastSpokenByKey[key] = now
        spokenTimesByKey[key] = recent + [now]
        return true
    }

    private func coalesce(_ text: String, kind: TranscriptEntry.Kind, at now: Date) {
        if var last = transcript.last, last.text == text, last.kind == kind,
           now.timeIntervalSince(last.date) < Self.coalesceWindow {
            last.count += 1
            last.date = now
            transcript[transcript.count - 1] = last
            return
        }
        append(text, kind: kind, at: now)
    }

    private func append(_ text: String, kind: TranscriptEntry.Kind, at now: Date) {
        transcript.append(TranscriptEntry(date: now, text: text, kind: kind))
        if transcript.count > Self.maxTranscriptEntries {
            transcript.removeFirst(transcript.count - Self.maxTranscriptEntries)
        }
    }
}
