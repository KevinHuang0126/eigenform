import CoreGraphics

/// Pure geometry helpers for the exercise analyzers.
///
/// All functions expect points in **metric space** (see `BodyPose.metricPoint(_:)`),
/// where x and y share the same physical unit. Feeding raw normalized coordinates
/// in here produces distorted angles on non-square frames.
enum BiomechanicsCalculator {

    /// Interior angle in degrees at `vertex`, formed by the rays toward `a` and `b`.
    /// Returns nil when either ray is degenerate (coincident points).
    static func angleDegrees(at vertex: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat? {
        let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
        let v2 = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
        let m1 = hypot(v1.dx, v1.dy)
        let m2 = hypot(v2.dx, v2.dy)
        guard m1 > .ulpOfOne, m2 > .ulpOfOne else { return nil }
        let cosine = (v1.dx * v2.dx + v1.dy * v2.dy) / (m1 * m2)
        return acos(max(-1, min(1, cosine))) * 180 / .pi
    }

    /// Perpendicular distance from `point` to the infinite line through `a` and `b`.
    /// Returns nil when `a` and `b` coincide.
    static func perpendicularDistance(of point: CGPoint,
                                      fromLineThrough a: CGPoint,
                                      and b: CGPoint) -> CGFloat? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > .ulpOfOne else { return nil }
        return abs(dx * (a.y - point.y) - dy * (a.x - point.x)) / length
    }

    /// Signed vertical offset of `point` relative to the line through `a` and `b`,
    /// evaluated at the point's x. Negative means the point sits **below** the line
    /// (toward the floor, in Vision's bottom-left-origin space) — for a pushup body
    /// line this reads as sagging hips; positive reads as piking.
    ///
    /// Returns nil when the line is near-vertical (body not horizontal enough for
    /// the reading to mean anything).
    static func verticalOffset(of point: CGPoint,
                               fromLineThrough a: CGPoint,
                               and b: CGPoint) -> CGFloat? {
        let dx = b.x - a.x
        guard abs(dx) > 0.05 else { return nil }
        let t = (point.x - a.x) / dx
        let lineY = a.y + t * (b.y - a.y)
        return point.y - lineY
    }

    /// Straight-line distance between two points.
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}
