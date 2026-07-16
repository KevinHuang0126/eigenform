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
        }
        .allowsHitTesting(false)
    }
}
