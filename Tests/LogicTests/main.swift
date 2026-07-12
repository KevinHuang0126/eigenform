// Eigenform logic test harness.
//
// Runs on macOS (no simulator needed): the biomechanics layer and the exercise
// state machines are pure Swift + CoreGraphics + Vision types, so they compile
// natively. Drives each analyzer with synthetic pose sequences and asserts on the
// emitted events. Run via Tests/run_tests.sh.

import CoreGraphics
import Foundation

// MARK: - Tiny assertion framework

var testCount = 0
var failureCount = 0
var currentSuite = ""

func suite(_ name: String) {
    currentSuite = name
    print("\n== \(name)")
}

func expect(_ condition: Bool, _ message: String,
            file: String = #file, line: Int = #line) {
    testCount += 1
    if condition {
        print("  ok  \(message)")
    } else {
        failureCount += 1
        print("  FAIL \(message)  (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String,
                               file: String = #file, line: Int = #line) {
    expect(actual == expected, "\(message) [got \(actual), want \(expected)]",
           file: file, line: line)
}

func expectClose(_ actual: CGFloat?, _ expected: CGFloat, tolerance: CGFloat = 0.5,
                 _ message: String, file: String = #file, line: Int = #line) {
    guard let actual else {
        expect(false, "\(message) [got nil, want \(expected)]", file: file, line: line)
        return
    }
    expect(abs(actual - expected) <= tolerance,
           "\(message) [got \(actual), want \(expected) ±\(tolerance)]",
           file: file, line: line)
}

// MARK: - Synthetic pose helpers

/// Portrait 720×1280 buffer, matching the capture pipeline.
let testImageSize = CGSize(width: 720, height: 1280)
let testAspect = testImageSize.width / testImageSize.height

/// Builds a pose from joints given in **metric space** (x and y in frame-height
/// units — the space all analyzer math runs in). Converts x back to normalized
/// storage so `BodyPose.metricPoint(_:)` round-trips to exactly these values.
func makePose(_ metricJoints: [BodyPose.Joint: CGPoint],
              confidence: Float = 0.9,
              confidenceOverrides: [BodyPose.Joint: Float] = [:]) -> BodyPose {
    var stored: [BodyPose.Joint: (location: CGPoint, confidence: Float)] = [:]
    for (joint, p) in metricJoints {
        stored[joint] = (CGPoint(x: p.x / testAspect, y: p.y),
                         confidenceOverrides[joint] ?? confidence)
    }
    return BodyPose(joints: stored, imageSize: testImageSize)
}

/// Feeds the same pose N times, collecting all events.
@discardableResult
func feed(_ analyzer: ExerciseAnalyzer, _ pose: BodyPose, frames: Int) -> [FormEvent] {
    var events: [FormEvent] = []
    for _ in 0..<frames {
        events.append(contentsOf: analyzer.process(pose))
    }
    return events
}

func reps(in events: [FormEvent]) -> Int {
    events.reduce(0) { count, event in
        if case .repCompleted = event { return count + 1 }
        return count
    }
}

func faults(in events: [FormEvent], category: FaultCategory) -> Int {
    events.reduce(0) { count, event in
        if case .fault(_, let c) = event, c == category { return count + 1 }
        return count
    }
}

// MARK: - BiomechanicsCalculator

suite("BiomechanicsCalculator.angleDegrees")
expectClose(
    BiomechanicsCalculator.angleDegrees(at: .zero,
                                        from: CGPoint(x: 1, y: 0),
                                        to: CGPoint(x: 0, y: 1)),
    90, "right angle")
expectClose(
    BiomechanicsCalculator.angleDegrees(at: .zero,
                                        from: CGPoint(x: 1, y: 0),
                                        to: CGPoint(x: -1, y: 0)),
    180, "straight line")
expectClose(
    BiomechanicsCalculator.angleDegrees(at: .zero,
                                        from: CGPoint(x: 1, y: 0),
                                        to: CGPoint(x: 1, y: 0)),
    0, "coincident rays")
expect(
    BiomechanicsCalculator.angleDegrees(at: .zero, from: .zero, to: CGPoint(x: 1, y: 0)) == nil,
    "degenerate ray returns nil")

suite("BiomechanicsCalculator.perpendicularDistance")
expectClose(
    BiomechanicsCalculator.perpendicularDistance(of: CGPoint(x: 0.5, y: 1),
                                                 fromLineThrough: .zero,
                                                 and: CGPoint(x: 1, y: 0)),
    1, tolerance: 0.001, "point above horizontal line")
expect(
    BiomechanicsCalculator.perpendicularDistance(of: .zero,
                                                 fromLineThrough: CGPoint(x: 1, y: 1),
                                                 and: CGPoint(x: 1, y: 1)) == nil,
    "degenerate line returns nil")

suite("BiomechanicsCalculator.verticalOffset")
expectClose(
    BiomechanicsCalculator.verticalOffset(of: CGPoint(x: 0.5, y: 0.3),
                                          fromLineThrough: CGPoint(x: 0, y: 0.5),
                                          and: CGPoint(x: 1, y: 0.5)),
    -0.2, tolerance: 0.001, "below the line is negative (sag direction)")
expectClose(
    BiomechanicsCalculator.verticalOffset(of: CGPoint(x: 0.5, y: 0.8),
                                          fromLineThrough: CGPoint(x: 0, y: 0.5),
                                          and: CGPoint(x: 1, y: 0.5)),
    0.3, tolerance: 0.001, "above the line is positive (pike direction)")
expect(
    BiomechanicsCalculator.verticalOffset(of: .zero,
                                          fromLineThrough: CGPoint(x: 0.5, y: 0),
                                          and: CGPoint(x: 0.5, y: 1)) == nil,
    "near-vertical line returns nil")

// MARK: - ConsecutiveFrameGate

suite("ConsecutiveFrameGate")
var gate = ConsecutiveFrameGate(threshold: 3)
expectEqual(gate.update(true), false, "frame 1 not yet open")
expectEqual(gate.update(true), false, "frame 2 not yet open")
expectEqual(gate.update(true), true, "frame 3 opens the gate")
expectEqual(gate.update(true), true, "stays open while condition holds")
expectEqual(gate.update(false), false, "single false frame closes it")
expectEqual(gate.update(true), false, "streak restarts from zero")

// MARK: - LatchingFaultGate

suite("LatchingFaultGate")
var latch = LatchingFaultGate(fireThreshold: 3, rearmThreshold: 5)
expectEqual(latch.update(true), false, "frame 1 silent")
expectEqual(latch.update(true), false, "frame 2 silent")
expectEqual(latch.update(true), true, "frame 3 fires")
var latchFires = 0
for _ in 0..<100 where latch.update(true) { latchFires += 1 }
expectEqual(latchFires, 0, "persistent condition never re-fires")

// 4 clear frames < rearmThreshold: the latch holds through the next occurrence.
for _ in 0..<4 { latch.update(false) }
latchFires = 0
for _ in 0..<5 where latch.update(true) { latchFires += 1 }
expectEqual(latchFires, 0, "insufficient clear streak keeps the latch")

// 5 clear frames re-arm; the next sustained occurrence fires again.
for _ in 0..<5 { latch.update(false) }
expectEqual(latch.update(true), false, "re-armed gate still debounces frame 1")
latch.update(true)
expectEqual(latch.update(true), true, "re-armed gate fires on a new occurrence")

latch.rearm()
latch.update(true)
latch.update(true)
expectEqual(latch.update(true), true, "rearm() re-arms immediately")

var jitterLatch = LatchingFaultGate(fireThreshold: 3, rearmThreshold: 5)
latchFires = 0
for _ in 0..<20 {
    if jitterLatch.update(true) { latchFires += 1 }
    if jitterLatch.update(true) { latchFires += 1 }
    if jitterLatch.update(false) { latchFires += 1 }
}
expectEqual(latchFires, 0, "sub-threshold jitter never fires")

// MARK: - CueArbiter

suite("CueArbiter")
let arbiterEpoch = Date(timeIntervalSinceReferenceDate: 0)
func arbiterTime(_ seconds: TimeInterval) -> Date {
    arbiterEpoch.addingTimeInterval(seconds)
}
let heelFault: [FormEvent] = [.fault(cue: "Keep your heels down", category: .heelLift)]

let cadence = CueArbiter()
expectEqual(cadence.handle(heelFault, at: arbiterTime(0)), ["Keep your heels down"],
            "first fault speaks immediately")
expectEqual(cadence.handle(heelFault, at: arbiterTime(3)).isEmpty, true,
            "repeat inside the base cooldown is silent")
expectEqual(cadence.transcript.count, 1, "silenced repeat coalesces into the same row")
expectEqual(cadence.transcript.last?.count, 2, "coalesced row counts both occurrences")
expectEqual(cadence.handle(heelFault, at: arbiterTime(6)).count, 1,
            "speaks again after the 6s base cooldown")
expectEqual(cadence.handle(heelFault, at: arbiterTime(12)).isEmpty, true,
            "cooldown escalated to 12s — another 6s gap is now silent")
expectEqual(cadence.handle(heelFault, at: arbiterTime(18)).count, 1,
            "speaks after the escalated 12s gap")
expectEqual(cadence.transcript.count, 1, "steady repeats stay one transcript row")
expectEqual(cadence.transcript.last?.count, 5, "row keeps counting suppressed repeats")
expectEqual(cadence.handle(heelFault, at: arbiterTime(42)).isEmpty, true,
            "4th speak inside the rolling 60s window is capped")
expectEqual(cadence.transcript.count, 2, "a repeat after the coalesce window opens a new row")
expectEqual(cadence.handle(heelFault, at: arbiterTime(61)).count, 1,
            "long silence forgets the escalation and speaks at base cadence")

let alwaysSpeak = CueArbiter()
expectEqual(alwaysSpeak.handle([.repCompleted(count: 1)], at: arbiterTime(0)), ["1"],
            "rep counts always speak")
expectEqual(alwaysSpeak.handle([.repCompleted(count: 2)], at: arbiterTime(1)), ["2"],
            "back-to-back reps are never throttled")
expectEqual(alwaysSpeak.handle([.setupGuidance("Turn sideways to the camera")],
                               at: arbiterTime(2)).count, 1,
            "guidance speaks")
expectEqual(alwaysSpeak.handle([.setupGuidance("Step back")], at: arbiterTime(2)).count, 1,
            "distinct guidance texts don't throttle each other")
expectEqual(alwaysSpeak.handle([.setupGuidance("Step back")], at: arbiterTime(4)).isEmpty, true,
            "identical guidance respects its own cooldown")

let phases = CueArbiter()
_ = phases.handle([.phaseChanged("Descending")], at: arbiterTime(0))
_ = phases.handle([.phaseChanged("Descending")], at: arbiterTime(1))
expectEqual(phases.transcript.count, 1, "identical back-to-back phase rows are dropped")
phases.clear()
expectEqual(phases.transcript.isEmpty, true, "clear() empties the transcript")
expectEqual(phases.handle(heelFault, at: arbiterTime(2)).count, 1,
            "clear() resets cooldowns — fault speaks immediately")

// MARK: - Curl analyzer

suite("CurlAnalyzer")
let curl = CurlAnalyzer()

// Right arm, metric space. Extended: wrist hangs straight below the elbow (~180°).
// Flexed: wrist right next to the shoulder (~4°).
let curlExtended = makePose([
    .rightShoulder: CGPoint(x: 0.30, y: 0.70),
    .rightElbow: CGPoint(x: 0.30, y: 0.50),
    .rightWrist: CGPoint(x: 0.30, y: 0.30),
])
let curlFlexed = makePose([
    .rightShoulder: CGPoint(x: 0.30, y: 0.70),
    .rightElbow: CGPoint(x: 0.30, y: 0.50),
    .rightWrist: CGPoint(x: 0.31, y: 0.68),
])

var curlEvents = feed(curl, curlExtended, frames: 4)
expectEqual(reps(in: curlEvents), 0, "extension alone counts nothing")
curlEvents = feed(curl, curlFlexed, frames: 4)
expectEqual(reps(in: curlEvents), 1, "extension → flexion counts one rep")
curlEvents = feed(curl, curlFlexed, frames: 20)
expectEqual(reps(in: curlEvents), 0, "holding flexion never double-counts")
curlEvents = feed(curl, curlExtended, frames: 4) + feed(curl, curlFlexed, frames: 4)
expectEqual(reps(in: curlEvents), 1, "second full cycle counts a second rep")
expectEqual(curl.repCount, 2, "running total is 2")

// Debounce: 2-frame flexion blips must not register (threshold is 3).
let curlBlips = CurlAnalyzer()
feed(curlBlips, curlExtended, frames: 4)
for _ in 0..<5 {
    feed(curlBlips, curlFlexed, frames: 2)
    feed(curlBlips, curlExtended, frames: 2)
}
expectEqual(curlBlips.repCount, 0, "2-frame jitter blips never count reps")

// Occluded arm: no events, no crash.
let curlOccluded = CurlAnalyzer()
let lowConfidence = makePose([
    .rightShoulder: CGPoint(x: 0.3, y: 0.7),
    .rightElbow: CGPoint(x: 0.3, y: 0.5),
    .rightWrist: CGPoint(x: 0.3, y: 0.3),
], confidence: 0.1)
let occludedEvents = feed(curlOccluded, lowConfidence, frames: 10)
expectEqual(reps(in: occludedEvents), 0, "low-confidence joints are ignored")

// MARK: - Squat analyzer

suite("SquatAnalyzer")

// Side view, left leg. Knee fixed; hip travels down and back.
func squatPose(hip: CGPoint, ankleY: CGFloat = 0.15) -> BodyPose {
    makePose([
        .leftHip: hip,
        .leftKnee: CGPoint(x: 0.50, y: 0.35),
        .leftAnkle: CGPoint(x: 0.50, y: ankleY),
    ])
}
let squatStanding = squatPose(hip: CGPoint(x: 0.50, y: 0.55))   // knee ~180°
let squatMid = squatPose(hip: CGPoint(x: 0.57, y: 0.42))        // knee ~135°
let squatDeep = squatPose(hip: CGPoint(x: 0.62, y: 0.34))       // hip below knee, ~85°

let squat = SquatAnalyzer()
feed(squat, squatStanding, frames: 6)                            // calibrate ankle baseline
feed(squat, squatMid, frames: 4)                                 // descending
feed(squat, squatDeep, frames: 4)                                // depth reached
feed(squat, squatMid, frames: 4)                                 // ascending
let squatLockout = feed(squat, squatStanding, frames: 4)
expectEqual(reps(in: squatLockout), 1, "full-depth squat counts a rep")
expectEqual(faults(in: squatLockout, category: .depth), 0, "no depth fault on a good rep")

// Shallow squat: never breaks parallel → fault, no rep. The standing feed needs
// 3 frames for the ascent gate plus 3 for the lockout gate (they open in series
// here, since the mid position never rebounds enough to flip the phase itself).
let shallow = SquatAnalyzer()
feed(shallow, squatStanding, frames: 6)
feed(shallow, squatMid, frames: 6)
let shallowLockout = feed(shallow, squatStanding, frames: 8)
expectEqual(reps(in: shallowLockout), 0, "shallow squat does not count")
expectEqual(faults(in: shallowLockout, category: .depth), 1, "shallow squat triggers depth cue")

// Heel lift mid-rep: ankle rises above its calibrated standing height. The
// standing feed must cover the calibration window; the shank here is 0.20, so the
// tolerance works out to 0.04 and the 0.05 rise clears it. Latched: a persistent
// lift fires exactly once.
let heels = SquatAnalyzer()
feed(heels, squatStanding, frames: 20)
let heelUp = squatPose(hip: CGPoint(x: 0.57, y: 0.42), ankleY: 0.20)
let heelEvents = feed(heels, heelUp, frames: 60)
expectEqual(faults(in: heelEvents, category: .heelLift), 1,
            "persistent heel lift cues exactly once per occurrence")

// Heels return down long enough to re-arm, then lift again: a second occurrence.
feed(heels, squatMid, frames: 15)
let secondLift = feed(heels, heelUp, frames: 10)
expectEqual(faults(in: secondLift, category: .heelLift), 1,
            "a fresh heel-lift occurrence cues again")

// A rise inside the shank-scaled tolerance is posture noise, not a heel lift.
let steadyHeels = SquatAnalyzer()
feed(steadyHeels, squatStanding, frames: 20)
let smallRise = feed(steadyHeels, squatPose(hip: CGPoint(x: 0.57, y: 0.42), ankleY: 0.18),
                     frames: 60)
expectEqual(faults(in: smallRise, category: .heelLift), 0,
            "sub-tolerance ankle rise stays quiet")

// A low-confidence ankle (drifting keypoint) must not be judged.
let blurryAnkle = SquatAnalyzer()
feed(blurryAnkle, squatStanding, frames: 20)
let lowConfLift = makePose([
    .leftHip: CGPoint(x: 0.57, y: 0.42),
    .leftKnee: CGPoint(x: 0.50, y: 0.35),
    .leftAnkle: CGPoint(x: 0.50, y: 0.20),
], confidenceOverrides: [.leftAnkle: 0.4])
let lowConfEvents = feed(blurryAnkle, lowConfLift, frames: 60)
expectEqual(faults(in: lowConfEvents, category: .heelLift), 0,
            "low-confidence ankle frames skip the heel check")

// MARK: - Pushup analyzer

suite("PushupAnalyzer")

// Side view, horizontal body, left side. Body line fixed; elbow position
// synthesizes the elbow angle.
func pushupPose(elbow: CGPoint, hipY: CGFloat = 0.45) -> BodyPose {
    makePose([
        .leftShoulder: CGPoint(x: 0.30, y: 0.50),
        .leftElbow: elbow,
        .leftWrist: CGPoint(x: 0.30, y: 0.20),
        .leftHip: CGPoint(x: 0.55, y: hipY),
        .leftAnkle: CGPoint(x: 0.80, y: 0.40),
    ])
}
let pushupLockout = pushupPose(elbow: CGPoint(x: 0.30, y: 0.35))  // ~180°
let pushupMid = pushupPose(elbow: CGPoint(x: 0.35, y: 0.35))      // ~143°
let pushupDeep = pushupPose(elbow: CGPoint(x: 0.48, y: 0.35))     // ~80°

// The elbow angle is EMA-smoothed, so transitions need a few extra frames for the
// smoothed value to cross each threshold.
let pushup = PushupAnalyzer()
feed(pushup, pushupLockout, frames: 4)
feed(pushup, pushupMid, frames: 4)
feed(pushup, pushupDeep, frames: 8)
feed(pushup, pushupMid, frames: 4)
let pushupTop = feed(pushup, pushupLockout, frames: 4)
expectEqual(reps(in: pushupTop), 1, "full-depth pushup counts a rep")

// Half rep: bends to ~107° — below the 135° descent threshold, never below 90°,
// shoulder height unchanged → depth cue, no count.
let pushupHalf = pushupPose(elbow: CGPoint(x: 0.41, y: 0.35))
let halfRep = PushupAnalyzer()
feed(halfRep, pushupLockout, frames: 4)
feed(halfRep, pushupHalf, frames: 6)
let halfRepTop = feed(halfRep, pushupLockout, frames: 8)
expectEqual(reps(in: halfRepTop), 0, "half pushup does not count")
expectEqual(faults(in: halfRepTop, category: .depth), 1, "half pushup triggers go-lower cue")

// Camera compression: the elbow angle only reaches ~113°, but the shoulder drops
// well past half its lockout height above the wrist — the Y-drop path counts it.
let compressedDeep = makePose([
    .leftShoulder: CGPoint(x: 0.32, y: 0.32),
    .leftElbow: CGPoint(x: 0.35, y: 0.27),
    .leftWrist: CGPoint(x: 0.30, y: 0.20),
    .leftHip: CGPoint(x: 0.55, y: 0.36),
    .leftAnkle: CGPoint(x: 0.80, y: 0.40),
])
let compressed = PushupAnalyzer()
feed(compressed, pushupLockout, frames: 6)
feed(compressed, compressedDeep, frames: 10)
feed(compressed, pushupMid, frames: 6)
let compressedTop = feed(compressed, pushupLockout, frames: 6)
expectEqual(reps(in: compressedTop), 1, "shoulder drop registers depth despite a compressed elbow angle")

// Sagging hips: hip well below the shoulder–ankle line. Latched: a persistent sag
// fires exactly once.
let sag = PushupAnalyzer()
let sagEvents = feed(sag, pushupPose(elbow: CGPoint(x: 0.30, y: 0.35), hipY: 0.38), frames: 60)
expectEqual(faults(in: sagEvents, category: .hipSag), 1, "persistent sag cues exactly once")
expectEqual(faults(in: sagEvents, category: .hipPike), 0, "no pike cue while sagging")

// Piking: hip well above the line.
let pike = PushupAnalyzer()
let pikeEvents = feed(pike, pushupPose(elbow: CGPoint(x: 0.30, y: 0.35), hipY: 0.52), frames: 60)
expectEqual(faults(in: pikeEvents, category: .hipPike), 1, "persistent pike cues exactly once")
expectEqual(faults(in: pikeEvents, category: .hipSag), 0, "no sag cue while piking")

// MARK: - Pullup analyzer

suite("PullupAnalyzer")

// Facing view. Wrists overhead at y 0.75; the head moves between hang and top.
// Y-only logic, so metric-vs-normalized x is irrelevant here. Head and wrist
// heights are EMA-smoothed, so transitions need a few extra frames.
func pullupPose(noseY: CGFloat,
                confidenceOverrides: [BodyPose.Joint: Float] = [:]) -> BodyPose {
    makePose([
        .nose: CGPoint(x: 0.50, y: noseY),
        .leftWrist: CGPoint(x: 0.40, y: 0.75),
        .rightWrist: CGPoint(x: 0.60, y: 0.75),
        .leftShoulder: CGPoint(x: 0.40, y: 0.60),
        .rightShoulder: CGPoint(x: 0.60, y: 0.60),
    ], confidenceOverrides: confidenceOverrides)
}
let hang = pullupPose(noseY: 0.62)      // head well below wrists
let top = pullupPose(noseY: 0.80)       // head clears the wrist line + margin

let pullup = PullupAnalyzer()
feed(pullup, hang, frames: 4)
var pullupEvents = feed(pullup, top, frames: 8)
expectEqual(reps(in: pullupEvents), 1, "chin over bar counts a rep")
pullupEvents = feed(pullup, top, frames: 20)
expectEqual(reps(in: pullupEvents), 0, "hanging out at the top never double-counts")
pullupEvents = feed(pullup, hang, frames: 8) + feed(pullup, top, frames: 8)
expectEqual(reps(in: pullupEvents), 1, "full return to dead hang arms the next rep")
expectEqual(pullup.repCount, 2, "running total is 2")

// Partial: the head rises but never clears the wrists, then returns — no rep, one
// pull-higher cue on the way back down.
let partial = PullupAnalyzer()
feed(partial, hang, frames: 4)
feed(partial, pullupPose(noseY: 0.72), frames: 6)
let partialReturn = feed(partial, hang, frames: 8)
expectEqual(partial.repCount, 0, "partial pullup does not count")
expectEqual(faults(in: partialReturn, category: .depth), 1,
            "returning to dead hang after a partial cues exactly once")

// Jitter hovering at the wrist line must not mint reps.
let jitter = PullupAnalyzer()
feed(jitter, hang, frames: 4)
var jitterEvents: [FormEvent] = []
for _ in 0..<15 {
    jitterEvents += feed(jitter, pullupPose(noseY: 0.765), frames: 1)
    jitterEvents += feed(jitter, pullupPose(noseY: 0.735), frames: 1)
}
expectEqual(reps(in: jitterEvents), 0, "jitter at the wrist line never counts reps")

// Head tilted back at the top: the nose drops below the confidence floor, but the
// ears carry the head line and the rep still counts.
func pullupPoseEars(headY: CGFloat) -> BodyPose {
    makePose([
        .nose: CGPoint(x: 0.50, y: headY),
        .leftEar: CGPoint(x: 0.46, y: headY),
        .rightEar: CGPoint(x: 0.54, y: headY),
        .leftWrist: CGPoint(x: 0.40, y: 0.75),
        .rightWrist: CGPoint(x: 0.60, y: 0.75),
        .leftShoulder: CGPoint(x: 0.40, y: 0.60),
        .rightShoulder: CGPoint(x: 0.60, y: 0.60),
    ], confidenceOverrides: [.nose: 0.1])
}
let earFallback = PullupAnalyzer()
feed(earFallback, pullupPoseEars(headY: 0.62), frames: 4)
let earEvents = feed(earFallback, pullupPoseEars(headY: 0.80), frames: 8)
expectEqual(reps(in: earEvents), 1, "ears carry the head line when the nose is lost")

// One misdetected wrist far from the other: trust the confident one, keep counting.
func mismatchPose(noseY: CGFloat) -> BodyPose {
    makePose([
        .nose: CGPoint(x: 0.50, y: noseY),
        .leftWrist: CGPoint(x: 0.40, y: 0.75),
        .rightWrist: CGPoint(x: 0.60, y: 0.55),
        .leftShoulder: CGPoint(x: 0.40, y: 0.60),
        .rightShoulder: CGPoint(x: 0.60, y: 0.60),
    ], confidenceOverrides: [.rightWrist: 0.4])
}
let mismatch = PullupAnalyzer()
feed(mismatch, mismatchPose(noseY: 0.62), frames: 4)
let mismatchEvents = feed(mismatch, mismatchPose(noseY: 0.80), frames: 8)
expectEqual(reps(in: mismatchEvents), 1, "a misdetected wrist doesn't break the bar line")

// Arms not overhead → setup guidance, no rep machinery.
let noBar = PullupAnalyzer()
let noBarPose = makePose([
    .nose: CGPoint(x: 0.50, y: 0.70),
    .leftWrist: CGPoint(x: 0.40, y: 0.40),
    .rightWrist: CGPoint(x: 0.60, y: 0.40),
    .leftShoulder: CGPoint(x: 0.40, y: 0.60),
    .rightShoulder: CGPoint(x: 0.60, y: 0.60),
])
let noBarEvents = feed(noBar, noBarPose, frames: 50)
expect(noBarEvents.contains { if case .setupGuidance = $0 { return true }; return false },
       "wrists below shoulders produce setup guidance")
expectEqual(reps(in: noBarEvents), 0, "no reps without hanging from a bar")

// MARK: - Reset behavior

suite("Analyzer reset")
curl.reset()
expectEqual(curl.repCount, 0, "reset clears the rep count")
let postResetEvents = feed(curl, curlExtended, frames: 4) + feed(curl, curlFlexed, frames: 4)
expectEqual(reps(in: postResetEvents), 1, "analyzer works normally after reset")

// MARK: - Summary

print("\n\(testCount) assertions, \(failureCount) failures")
exit(failureCount == 0 ? 0 : 1)
