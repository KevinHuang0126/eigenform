# Todo

## History (done — verified 2026-07-19)

- [x] Run the SQL in `Eigenform/docs/HISTORY_SETUP.md` to create the
      `workouts` table (until then, saves queue on-device and History shows a
      pointer to that doc).
- [x] On-device: finish a set, confirm it appears under History (clock button
      on home) and in the dashboard's Table Editor; second account sees an
      empty history (RLS).

## Joint angles (view-aware as of 2026-07-19)

- [x] Make angle mode view-aware: `AngleVisibilityModel` classifies frontal vs
      sagittal from shoulder/hip gap (normalized by torso length) and hides
      joints whose 2D angle is meaningless for that view, with a foreshortening
      backstop for in-between orientations. Example: camera-facing curl shows
      shoulders/hips only; elbow angles appear side-on.

## Voice (decision deferred — no date set)

- [ ] Pick a path for shipping a good coach voice out of the box (Apple's
      premium/enhanced voices can't be bundled or auto-downloaded; the app
      already auto-uses one if the user has installed it). Options:
      1. Pre-recorded cue bank: generate/record the fixed cue set once
         (paid TTS or voice actor), ship as audio assets with synthesizer
         fallback. Best quality + plug and play; new cues need new clips.
      2. Bundle an open-source on-device TTS (Piper/sherpa-onnx): free,
         decent quality, but ~30–60 MB and breaks the zero-dependency claim.
      3. Status quo + first-run tip pointing users at Settings →
         Accessibility → Spoken Content → Voices to download a premium voice.

## Camera / session (idea only — undecided)

- [ ] Possible feature: let users track sets and advance to the next set for
      an exercise from inside the camera interface. Reservation: it could
      dilute the app's main idea of form tracking — worth weighing before
      building. Note only for now.

## Auth

- [ ] Guest mode: future iterations might let users try the app without an
      account (the wall added 2026-07-12 requires sign-in), with accounts
      unlocking all features — e.g. history/sync — and local guest data
      migrating into the account on sign-up. History note: guest sets could
      reuse `HistoryStore`'s pending queue as the local store, flushing on
      sign-up.
- [ ] `SupabaseConfig.swift` has real credentials; finish the dashboard-side
      checklist in `Eigenform/docs/AUTH_SETUP.md` (redirect URLs, email
      provider settings, `delete_user` RPC) if not already done.

## General (done 2026-07-15; needs on-device look)

- [x] make the mini figures have white dots, and simpfly the figures so that
      the image doesn't look super cramped (white figures on the icon's green
      bands — each chip reads as a mini app icon; fewer joint dots, pull-up
      bar removed)
- [x] Change eigenform to -> EigenForm in all places (display strings only;
      bundle ID, eigenform:// scheme, and target/type names intentionally
      unchanged)
- [x] change the logo that is used inside the acutual app to be the exact one
      used as the app icon. This kind of uniformity can help improve the app's
      feel of being put together. (lambda extracted from AppIcon.png into
      Assets.xcassets/LogoMark, template-rendered with the band gradient via
      EFLogoMark in Theme.swift)
