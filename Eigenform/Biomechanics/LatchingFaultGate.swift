/// Turns a per-frame boolean condition into one event per *occurrence*: `update(_:)`
/// returns true only on the frame the condition has held for `fireThreshold`
/// consecutive frames, then latches silent until the condition has been clear for
/// `rearmThreshold` consecutive frames (the occurrence ended) or `rearm()` is called
/// at a rep boundary. This is what keeps a persistent form fault from re-firing
/// every few frames — the fault event means "occurrence started", not "condition
/// sampled true" (ADR-003).
struct LatchingFaultGate {
    let fireThreshold: Int
    let rearmThreshold: Int

    private var trueStreak = 0
    private var falseStreak = 0
    private var latched = false

    init(fireThreshold: Int = 3, rearmThreshold: Int = 10) {
        self.fireThreshold = fireThreshold
        self.rearmThreshold = rearmThreshold
    }

    @discardableResult
    mutating func update(_ condition: Bool) -> Bool {
        if condition {
            trueStreak += 1
            falseStreak = 0
            if !latched, trueStreak >= fireThreshold {
                latched = true
                return true
            }
        } else {
            falseStreak += 1
            trueStreak = 0
            if latched, falseStreak >= rearmThreshold {
                latched = false
            }
        }
        return false
    }

    mutating func rearm() {
        trueStreak = 0
        falseStreak = 0
        latched = false
    }
}
