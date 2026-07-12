# Live Testing Checklist — Landscape Mode

These checks require a **physical iOS device** (the camera has no feed in the simulator
and pose detection needs a real body). Run the app on-device and walk through each item.

## Setup
- [ ] Install the Debug build on a physical iPhone (and iPad, if available).
- [ ] Grant camera permission on first launch.

## Core rotation behavior
- [ ] **Portrait unchanged** — held portrait, the preview is upright, the skeleton stays
      glued to the body, and a curl/squat counts reps exactly as before this change.
- [ ] **Landscape framing** — rotate to landscape: the preview fills the screen upright
      (not sideways or letterboxed) and the feed is visibly **wider** than in portrait.
- [ ] **Skeleton tracking in landscape** — the overlay tracks the body with no drift and
      no scale mismatch against the preview.

## Motivating case
- [ ] **Pushup end-to-end (landscape)** — get into a side-on pushup: the "horizontal body"
      gate passes, hip-sag/pike cues fire correctly, and reps count on lockout. This
      confirms "higher-Y = world-up" survived the device-tracked rotation.

## Edge cases
- [ ] **Mid-set rotation** — rotate portrait ↔ landscape while a set is in progress:
      preview, skeleton, and rep state stay coherent (no crash, no frozen feed).
- [ ] **Front camera in landscape** — flip to the front camera in landscape and confirm
      mirroring keeps the skeleton glued to the body. *(Highest-risk item: the only place a
      rotation/mirror-axis mismatch could surface — check this first.)*

## Device coverage
- [ ] iPhone — both LandscapeLeft and LandscapeRight (rotate each way).
- [ ] iPad — portrait and landscape (both directions).

---
_Already verified off-device: logic tests (`Tests/run_tests.sh`, 80/0), clean `xcodebuild`,
and the landscape orientation keys in the compiled Info.plist._
