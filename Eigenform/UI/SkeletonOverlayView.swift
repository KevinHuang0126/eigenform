import SwiftUI

/// The live skeleton, drawn in the app icon's visual language: round-capped
/// bones with a soft glow and solid white circular joints — the on-screen body
/// becomes the lambda from the logo. `tint` is mint normally and flashes coral
/// on a form fault (driven by `SessionView`).
///
/// Converts Vision normalized points (bottom-left origin) into view coordinates,
/// replicating the preview layer's `.resizeAspectFill` mapping so the skeleton
/// stays glued to the on-screen body.
struct SkeletonOverlayView: View {
    let frame: SkeletonFrame?
    var tint: Color = EF.mint
    /// Angle mode: annotate each hinge joint with its live interior angle.
    var showAngles: Bool = false

    /// Radius of the angle arc drawn inside each annotated joint.
    private static let arcRadius: CGFloat = 14
    /// Distance from the joint to the degree label, along the interior bisector.
    private static let labelOffset: CGFloat = 32
    /// Rays shorter than this (in view points) give jittery, meaningless angles —
    /// skip the annotation rather than flash garbage.
    private static let minimumRayLength: CGFloat = 30

    var body: some View {
        Canvas { context, size in
            guard let frame, frame.imageSize.width > 0, frame.imageSize.height > 0 else { return }

            // Aspect-fill: scale the image to cover the view, center the overflow.
            let scale = max(size.width / frame.imageSize.width,
                            size.height / frame.imageSize.height)
            let fitted = CGSize(width: frame.imageSize.width * scale,
                                height: frame.imageSize.height * scale)
            let offset = CGPoint(x: (size.width - fitted.width) / 2,
                                 y: (size.height - fitted.height) / 2)

            func convert(_ visionPoint: CGPoint) -> CGPoint {
                let x = frame.mirrored ? 1 - visionPoint.x : visionPoint.x
                // Vision y grows upward; the view's grows downward.
                let y = 1 - visionPoint.y
                return CGPoint(x: offset.x + x * fitted.width,
                               y: offset.y + y * fitted.height)
            }

            var bonePath = Path()
            for (a, b) in SkeletonFrame.bones {
                guard let pa = frame.joints[a], let pb = frame.joints[b] else { continue }
                bonePath.move(to: convert(pa))
                bonePath.addLine(to: convert(pb))
            }

            var glow = context
            glow.addFilter(.shadow(color: tint.opacity(0.85), radius: 7))
            glow.stroke(bonePath,
                        with: .color(tint.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            for point in frame.joints.values {
                let p = convert(point)
                let dot = CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
                context.fill(Path(ellipseIn: dot), with: .color(.white))
            }

            if showAngles {
                // The aspect-fill conversion is a uniform scale (plus a possible
                // mirror flip), so angles measured on view points equal the
                // metric-space angles the analyzers compute. Only vertices the
                // view-aware gate marked trustworthy are annotated.
                for triple in SkeletonFrame.angleJoints {
                    guard frame.visibleAngleVertices.contains(triple.vertex),
                          let jv = frame.joints[triple.vertex],
                          let ja = frame.joints[triple.a],
                          let jb = frame.joints[triple.b] else { continue }
                    drawAngle(context: context,
                              vertex: convert(jv), a: convert(ja), b: convert(jb))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// One joint annotation: an arc spanning the interior angle plus a degree
    /// readout floated along the angle's bisector, capsule-backed so it stays
    /// legible over the video feed.
    private func drawAngle(context: GraphicsContext, vertex: CGPoint, a: CGPoint, b: CGPoint) {
        guard BiomechanicsCalculator.distance(vertex, a) > Self.minimumRayLength,
              BiomechanicsCalculator.distance(vertex, b) > Self.minimumRayLength,
              let degrees = BiomechanicsCalculator.angleDegrees(at: vertex, from: a, to: b)
        else { return }

        let angleA = atan2(a.y - vertex.y, a.x - vertex.x)
        let angleB = atan2(b.y - vertex.y, b.x - vertex.x)
        // Shortest signed sweep from ray A to ray B — its magnitude is the
        // interior angle, so the arc always hugs the inside of the joint.
        var sweep = angleB - angleA
        if sweep > .pi { sweep -= 2 * .pi }
        if sweep < -.pi { sweep += 2 * .pi }

        var arc = Path()
        arc.addRelativeArc(center: vertex, radius: Self.arcRadius,
                           startAngle: .radians(angleA), delta: .radians(sweep))
        context.stroke(arc, with: .color(.white.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let bisector = angleA + sweep / 2
        let labelCenter = CGPoint(x: vertex.x + cos(bisector) * Self.labelOffset,
                                  y: vertex.y + sin(bisector) * Self.labelOffset)

        let label = context.resolve(
            Text("\(Int(degrees.rounded()))°")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white))
        let textSize = label.measure(in: CGSize(width: 60, height: 24))
        let capsule = CGRect(x: labelCenter.x - textSize.width / 2 - 5,
                             y: labelCenter.y - textSize.height / 2 - 2,
                             width: textSize.width + 10,
                             height: textSize.height + 4)
        context.fill(Path(roundedRect: capsule, cornerRadius: capsule.height / 2),
                     with: .color(.black.opacity(0.45)))
        context.draw(label, at: labelCenter, anchor: .center)
    }
}
