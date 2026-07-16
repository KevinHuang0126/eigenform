import SwiftUI

/// Hand-drawn mini skeleton for each exercise: the pose a body makes at the
/// movement's signature moment, in the exact language of the app icon — white
/// round-capped bones with circular joints and head node, sitting on the
/// icon's green bands (`EF.iconGradient` behind it at the call sites).
/// Replaces SF Symbols on the home cards so the app's iconography is its own.
struct ExerciseGlyph: View {
    let exercise: Exercise
    var boneColor: Color = .white

    var body: some View {
        Canvas { context, size in
            let pose = Self.pose(for: exercise)
            // Poses are authored in a 24×24 box; scale to fit, centered.
            let s = min(size.width, size.height) / 24
            let dx = (size.width - 24 * s) / 2
            let dy = (size.height - 24 * s) / 2
            func pt(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * s + dx, y: p.y * s + dy)
            }

            var bones = Path()
            for (a, b) in pose.bones {
                bones.move(to: pt(a))
                bones.addLine(to: pt(b))
            }
            context.stroke(bones, with: .color(boneColor),
                           style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round))

            let head = pt(pose.head)
            let hr = 2.0 * s
            context.fill(Path(ellipseIn: CGRect(x: head.x - hr, y: head.y - hr,
                                                width: hr * 2, height: hr * 2)),
                         with: .color(.white))

            for joint in pose.joints {
                let p = pt(joint)
                let r = 1.5 * s
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(.white))
            }
        }
    }

    // MARK: Poses (24×24 space, y down)
    // Joint dots mark only the joints that define the movement; everything else
    // ends in a bare round cap, exactly like the icon's lambda.

    private struct Pose {
        var bones: [(CGPoint, CGPoint)]
        var joints: [CGPoint]
        var head: CGPoint
    }

    private static func pose(for exercise: Exercise) -> Pose {
        switch exercise {
        case .bicepCurl:
            // Standing side-on, elbow flexed at the top of the curl.
            let shoulder = CGPoint(x: 11.5, y: 7.8)
            let elbow = CGPoint(x: 14.8, y: 12.3)
            let wrist = CGPoint(x: 16.8, y: 7.2)
            let hip = CGPoint(x: 11.5, y: 14.5)
            return Pose(
                bones: [
                    (CGPoint(x: 11.5, y: 7.2), hip),                  // torso
                    (hip, CGPoint(x: 10.0, y: 21.5)),                 // rear leg
                    (hip, CGPoint(x: 13.0, y: 21.5)),                 // front leg
                    (shoulder, elbow),                                 // upper arm
                    (elbow, wrist),                                    // forearm, curled
                ],
                joints: [shoulder, elbow, wrist, hip],
                head: CGPoint(x: 11.5, y: 4.6))

        case .squat:
            // Side-on at depth: hips back, thigh near parallel, arms out for balance.
            let shoulder = CGPoint(x: 14.8, y: 8.2)
            let hip = CGPoint(x: 10.0, y: 14.2)
            let knee = CGPoint(x: 15.2, y: 16.4)
            let ankle = CGPoint(x: 13.8, y: 21.6)
            return Pose(
                bones: [
                    (shoulder, hip),                                   // leaning torso
                    (hip, knee),                                       // thigh
                    (knee, ankle),                                     // shin
                    (ankle, CGPoint(x: 16.8, y: 21.6)),               // foot
                    (shoulder, CGPoint(x: 20.2, y: 9.6)),             // arm forward
                ],
                joints: [shoulder, hip, knee],
                head: CGPoint(x: 16.0, y: 5.2))

        case .pushup:
            // Plank, elbow bent at the bottom of the rep.
            let shoulder = CGPoint(x: 6.0, y: 13.2)
            let hip = CGPoint(x: 13.0, y: 14.9)
            let elbow = CGPoint(x: 8.8, y: 16.8)
            return Pose(
                bones: [
                    (shoulder, hip),                                   // spine
                    (hip, CGPoint(x: 20.0, y: 16.6)),                 // legs
                    (shoulder, elbow),                                 // upper arm
                    (elbow, CGPoint(x: 6.8, y: 20.6)),                // forearm to floor
                ],
                joints: [shoulder, hip, elbow],
                head: CGPoint(x: 3.9, y: 10.6))

        case .pullup:
            // Facing the camera, hanging mid-pull, elbows bent.
            let leftElbow = CGPoint(x: 6.6, y: 7.8)
            let rightElbow = CGPoint(x: 17.4, y: 7.8)
            let leftShoulder = CGPoint(x: 9.6, y: 10.4)
            let rightShoulder = CGPoint(x: 14.4, y: 10.4)
            let hip = CGPoint(x: 12.0, y: 15.8)
            return Pose(
                bones: [
                    (CGPoint(x: 7.0, y: 3.6), leftElbow), (leftElbow, leftShoulder),
                    (CGPoint(x: 17.0, y: 3.6), rightElbow), (rightElbow, rightShoulder),
                    (leftShoulder, rightShoulder),                     // shoulder girdle
                    (CGPoint(x: 12.0, y: 10.4), hip),                 // torso
                    (hip, CGPoint(x: 10.6, y: 21.4)),                 // left leg
                    (hip, CGPoint(x: 13.4, y: 21.4)),                 // right leg
                ],
                joints: [leftElbow, rightElbow, hip],
                head: CGPoint(x: 12.0, y: 7.6))
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        ForEach(Exercise.allCases) { exercise in
            ExerciseGlyph(exercise: exercise)
                .frame(width: 32, height: 32)
                .frame(width: 46, height: 46)
                .background(EF.iconGradient, in: RoundedRectangle(cornerRadius: 14))
        }
    }
    .padding(30)
    .background(EF.paper)
}
