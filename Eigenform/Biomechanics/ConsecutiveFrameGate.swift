/// Debounces a per-frame boolean condition: `update(_:)` returns true only once the
/// condition has held for `threshold` consecutive frames. Any single false frame
/// resets the streak. This is the anti-jitter buffer required by the ADR (state
/// transitions must survive at least 3 frames before registering).
struct ConsecutiveFrameGate {
    let threshold: Int
    private var streak = 0

    init(threshold: Int = 3) {
        self.threshold = threshold
    }

    @discardableResult
    mutating func update(_ condition: Bool) -> Bool {
        streak = condition ? streak + 1 : 0
        return streak >= threshold
    }

    mutating func reset() {
        streak = 0
    }
}
