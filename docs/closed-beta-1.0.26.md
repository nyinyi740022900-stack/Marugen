# Closed beta 1.0.26 (31)

Submitted to Closed testing — Alpha for Google review on 2026-10-31, full rollout, replacing 30 (1.0.25), which Google approved and published to testers on 2026-10-31. Built from main at 66c5c37 plus the version bump. Publishing overview shows **Changes in review** (quick checks still running at submission; approval not yet confirmed).

- Release name: `1.0.26 (31) – Undo countdown`.
- Release notes (en-US): "After you remove a cart item or delete notifications, Undo now counts down from 5 and closes by itself."

## Changes

- Undo after removing a cart or checkout item, deleting notifications, or marking a live fish sold now counts down from 5 and closes by itself. Flutter keeps any snack bar with an action on screen until it is swiped away unless `persist` is false, so these bars used to stay up.
- With a screen reader or switch access on, the Undo bar still waits for the user (no countdown), and the ticking number is hidden from screen readers.

## Production backend

No backend change.

## Verification

- `flutter analyze`: no issues. Flutter: 511 passed; the 4 failures are the print acceptance tests that need `pdftoppm` and local `output/` PDFs.
- New tests: countdown, auto-close, Undo, accessibility, and the cart and checkout screens (both screen tests fail on the previous code).

## Release artifact

`output/releases/marugen-1.0.26-31-undo-countdown.aab`, 85.3 MB (85,255,301 bytes), `jar verified` (upload key CN=Marugen Koi Farm). Merged manifest: versionCode 31, versionName 1.0.26; the live Stripe publishable key and production Supabase project are compiled in from `env/prod.json`. SHA-256: `ccf14d907dbd1134575a072adb36e5c6ad59925cf41250aaec0afcb18214c37f`. Play Console: 31 (1.0.26), API 24+, target SDK 36, Ready to release, 0 devices lost, 19.2 MB for new installs. The owner dragged the bundle into Play Console (the Chrome extension cannot upload files this large).

## iPhone build

The same source (1.0.26, build 31, `env/prod.json`) was built with `flutter build ios --release` and installed on the owner's iPhone 17 Pro Max with `xcrun devicectl device install app`; the device reports Marugen 1.0.26 (31). The free personal team (F8KLK8L5SY) cannot sign push or Sign in with Apple, so `Runner.entitlements` was emptied for the build and restored afterwards: push notifications and Apple sign-in do not work in this build, and the free provisioning profile expires after 7 days.
