import CoreGraphics
import Vision

/// Decides which hinge-joint angles are trustworthy to annotate on the skeleton
/// overlay for the current camera view.
///
/// Two gates, applied in order each frame:
/// 1. **View classification** — frontal vs sagittal (side-on) from the body's
///    lateral span (shoulder/hip gap) normalized by torso length. Each class
///    allows a fixed vertex set; oblique/"ambiguous" views only keep joints that
///    are meaningful in *both* classes (shoulders + hips).
/// 2. **Foreshortening backstop** — hide a surviving angle when either limb ray
///    is compressed well below its recent peak 2D length (limb pointing at the
///    lens, or an in-between orientation the classifier missed).
///
/// Per-vertex show/hide is debounced so labels don't strobe across the
/// hysteresis band. Stateful — call `reset()` on session reset, exercise switch,
/// or camera flip.
final class AngleVisibilityModel {

    typealias Joint = VNHumanBodyPoseObservation.JointName

    /// Joint triples whose interior angle the overlay can annotate — same set the
    /// analyzers reason about. Source of truth for both the visibility model and
    /// `SkeletonFrame` / the overlay.
    static let angleJoints: [(vertex: Joint, a: Joint, b: Joint)] = [
        (.leftElbow, .leftShoulder, .leftWrist),
        (.rightElbow, .rightShoulder, .rightWrist),
        (.leftKnee, .leftHip, .leftAnkle),
        (.rightKnee, .rightHip, .rightAnkle),
        (.leftHip, .leftShoulder, .leftKnee),
        (.rightHip, .rightShoulder, .rightKnee),
        (.leftShoulder, .leftElbow, .leftHip),
        (.rightShoulder, .rightElbow, .rightHip),
    ]

    // MARK: Thresholds

    /// EMA blend toward the latest lateral-ratio sample.
    static let ratioEMAAlpha: CGFloat = 0.2
    /// Enter frontal when smoothed lateral ratio exceeds this.
    static let enterFrontal: CGFloat = 0.45
    /// Leave frontal when smoothed ratio drops below this.
    static let leaveFrontal: CGFloat = 0.30
    /// Enter sagittal when smoothed ratio falls below this.
    static let enterSagittal: CGFloat = 0.18
    /// Leave sagittal when smoothed ratio rises above this.
    static let leaveSagittal: CGFloat = 0.32
    /// Hide an angle when either ray is shorter than this fraction of its
    /// slowly-decaying peak length.
    static let foreshorteningRatio: CGFloat = 0.60
    /// Per-frame decay on a segment's reference length when the current sample
    /// is shorter (`ref = max(len, ref * decay)`).
    static let segmentRefDecay: CGFloat = 0.995
    /// Consecutive contrary frames required before a vertex's shown state flips.
    static let debounceFrames = 3

    // MARK: State

    private enum ViewClass {
        case frontal
        case sagittal(BodySide)
        case ambiguous
    }

    private var smoothedRatio: CGFloat?
    private var viewClass: ViewClass = .ambiguous
    private var segmentRefs: [SegmentKey: CGFloat] = [:]
    private var currentlyVisible: Set<Joint> = []
    /// Pending flip: the desired visibility and how many consecutive frames have
    /// asked for it. Cleared once the flip commits or the desire matches current.
    private var pending: [Joint: (wantVisible: Bool, streak: Int)] = [:]

    /// Vertices whose angles should be drawn for this pose.
    func visibleVertices(for pose: BodyPose) -> Set<Joint> {
        updateViewClass(from: pose)
        let allowed = allowedVertices(for: viewClass)
        var candidates = Set<Joint>()
        for triple in Self.angleJoints {
            guard allowed.contains(triple.vertex) else { continue }
            guard pose[triple.vertex] != nil,
                  pose[triple.a] != nil,
                  pose[triple.b] != nil else { continue }
            guard !isForeshortened(vertex: triple.vertex, a: triple.a, b: triple.b,
                                   pose: pose) else { continue }
            candidates.insert(triple.vertex)
        }
        return debounce(candidates: candidates)
    }

    func reset() {
        smoothedRatio = nil
        viewClass = .ambiguous
        segmentRefs.removeAll()
        currentlyVisible.removeAll()
        pending.removeAll()
    }

    // MARK: View classification

    private func updateViewClass(from pose: BodyPose) {
        guard let ratio = lateralRatio(for: pose) else {
            viewClass = .ambiguous
            return
        }
        smoothedRatio = smoothedRatio.map {
            $0 * (1 - Self.ratioEMAAlpha) + ratio * Self.ratioEMAAlpha
        } ?? ratio
        let r = smoothedRatio!

        switch viewClass {
        case .frontal:
            if r < Self.enterSagittal {
                viewClass = .sagittal(nearSide(for: pose))
            } else if r < Self.leaveFrontal {
                viewClass = .ambiguous
            }
        case .sagittal:
            if r > Self.enterFrontal {
                viewClass = .frontal
            } else if r > Self.leaveSagittal {
                viewClass = .ambiguous
            } else {
                // Stay sagittal but refresh the near side as confidence shifts.
                viewClass = .sagittal(nearSide(for: pose))
            }
        case .ambiguous:
            if r > Self.enterFrontal {
                viewClass = .frontal
            } else if r < Self.enterSagittal {
                viewClass = .sagittal(nearSide(for: pose))
            }
        }
    }

    /// Mean of shoulder and hip x-gaps in metric space, divided by torso length
    /// (neck–root). Distance-invariant: a close frontal pose and a far one yield
    /// similar ratios. Nil when the torso or both lateral pairs are missing.
    private func lateralRatio(for pose: BodyPose) -> CGFloat? {
        guard let neck = pose.metricPoint(.neck),
              let root = pose.metricPoint(.root) else { return nil }
        let torso = BiomechanicsCalculator.distance(neck, root)
        guard torso > .ulpOfOne else { return nil }

        var gaps: [CGFloat] = []
        if let ls = pose.metricPoint(.leftShoulder),
           let rs = pose.metricPoint(.rightShoulder) {
            gaps.append(abs(ls.x - rs.x))
        }
        if let lh = pose.metricPoint(.leftHip),
           let rh = pose.metricPoint(.rightHip) {
            gaps.append(abs(lh.x - rh.x))
        }
        guard !gaps.isEmpty else { return nil }
        let meanGap = gaps.reduce(0, +) / CGFloat(gaps.count)
        return meanGap / torso
    }

    private func nearSide(for pose: BodyPose) -> BodySide {
        BodySide.preferred(for: pose,
                           left: [.leftShoulder, .leftElbow, .leftHip, .leftKnee],
                           right: [.rightShoulder, .rightElbow, .rightHip, .rightKnee])
    }

    private func allowedVertices(for view: ViewClass) -> Set<Joint> {
        switch view {
        case .frontal, .ambiguous:
            // Ambiguous = intersection of frontal and (either) sagittal: shoulders
            // + hips. Elbows/knees stay hidden until the view settles.
            return [
                .leftShoulder, .rightShoulder,
                .leftHip, .rightHip,
            ]
        case .sagittal(let side):
            return side == .left
                ? [.leftShoulder, .leftElbow, .leftHip, .leftKnee]
                : [.rightShoulder, .rightElbow, .rightHip, .rightKnee]
        }
    }

    // MARK: Foreshortening

    /// True when either ray of the angle triple is compressed below the
    /// foreshortening fraction of its peak reference length.
    private func isForeshortened(vertex: Joint, a: Joint, b: Joint,
                                 pose: BodyPose) -> Bool {
        guard let pv = pose.metricPoint(vertex),
              let pa = pose.metricPoint(a),
              let pb = pose.metricPoint(b) else { return true }

        let lenA = BiomechanicsCalculator.distance(pv, pa)
        let lenB = BiomechanicsCalculator.distance(pv, pb)
        let keyA = SegmentKey(vertex, a)
        let keyB = SegmentKey(vertex, b)

        let shortA = updateSegmentRef(keyA, length: lenA)
        let shortB = updateSegmentRef(keyB, length: lenB)
        return shortA || shortB
    }

    /// Updates the decaying peak for one segment. Returns true when the current
    /// length is foreshortened relative to that peak.
    private func updateSegmentRef(_ key: SegmentKey, length: CGFloat) -> Bool {
        if let ref = segmentRefs[key] {
            let next = max(length, ref * Self.segmentRefDecay)
            segmentRefs[key] = next
            return length < Self.foreshorteningRatio * next
        }
        segmentRefs[key] = length
        return false
    }

    // MARK: Debounce

    private func debounce(candidates: Set<Joint>) -> Set<Joint> {
        let watched = currentlyVisible
            .union(candidates)
            .union(pending.keys)
        for joint in watched {
            let want = candidates.contains(joint)
            let shown = currentlyVisible.contains(joint)
            if want == shown {
                pending[joint] = nil
                continue
            }
            let streak: Int
            if let pending = pending[joint], pending.wantVisible == want {
                streak = pending.streak + 1
            } else {
                streak = 1
            }
            if streak >= Self.debounceFrames {
                if want {
                    currentlyVisible.insert(joint)
                } else {
                    currentlyVisible.remove(joint)
                }
                pending[joint] = nil
            } else {
                pending[joint] = (want, streak)
            }
        }
        return currentlyVisible
    }

    private struct SegmentKey: Hashable {
        let a: Joint
        let b: Joint
        init(_ a: Joint, _ b: Joint) {
            self.a = a
            self.b = b
        }
    }
}
