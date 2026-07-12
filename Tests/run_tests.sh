#!/bin/bash
# Compiles the Eigenform logic layer (no UIKit/AVFoundation dependencies) together
# with the test harness and runs it natively on macOS. No simulator required.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${TMPDIR:-/tmp}/eigenform-logic-tests"
mkdir -p "$BUILD_DIR"

swiftc -o "$BUILD_DIR/logic-tests" \
    -swift-version 5 \
    Eigenform/PoseEstimation/BodyPose.swift \
    Eigenform/Biomechanics/BiomechanicsCalculator.swift \
    Eigenform/Biomechanics/ConsecutiveFrameGate.swift \
    Eigenform/Biomechanics/LatchingFaultGate.swift \
    Eigenform/Feedback/CueArbiter.swift \
    Eigenform/Exercises/Exercise.swift \
    Eigenform/Exercises/ExerciseAnalyzer.swift \
    Eigenform/Exercises/CurlAnalyzer.swift \
    Eigenform/Exercises/SquatAnalyzer.swift \
    Eigenform/Exercises/PushupAnalyzer.swift \
    Eigenform/Exercises/PullupAnalyzer.swift \
    Tests/LogicTests/main.swift

"$BUILD_DIR/logic-tests"
