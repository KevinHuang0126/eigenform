# Todo

## History (code done 2026-07-12; needs backend + on-device check)

- [ ] Run the SQL in `Eigenform/docs/HISTORY_SETUP.md` to create the
      `workouts` table (until then, saves queue on-device and History shows a
      pointer to that doc).
- [ ] On-device: finish a set, confirm it appears under History (clock button
      on home) and in the dashboard's Table Editor; second account sees an
      empty history (RLS).

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
