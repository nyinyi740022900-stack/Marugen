# Android closed beta 1.0.2 (7)

Submitted on 2026-10-11 through Chrome's extension connection to the existing Google Play Closed testing — Alpha track. The standard native file picker selected the bundle without changing extension permissions.

- Package: `com.marugen.marugen_app`.
- Release name: `1.0.2 (7) – Responsive layout improvements`.
- Build source: `323daab`; version recorded in pubspec: `1.0.2+7`.
- Signed bundle: `output/releases/marugen-1.0.2-7.aab` (ignored local artifact), 83,676,139 bytes.
- SHA-256: `ae652b4b6c3c00a54a0b9e602abe73ea077d1ba21a474def5150c47b37049f0d`.
- Release build succeeded; jarsigner reported `jar verified` with self-signed certificate, timestamp and ZIP streaming warnings. Play Console validation is recorded below after upload.
- Play Console accepted version 7 (1.0.2), API 24+, target SDK 36 and showed **Ready to release**. Previously supported devices were retained. Optimized new install size: 19 MB; update size: 5.79 MB.
- Console status after submission: **Changes in review**; quick checks were still running. Availability to testers is pending approval.
- Rollout: 100% of the existing Alpha track. Managed publishing was already off, so approval publishes the update automatically. Production, testers and countries were not changed.
- Evidence: `output/releases/closed-beta-1.0.2-review.png` (ignored local artifact).
- Flutter regression suite: 131 tests passed; analyzer reported no issues; whitespace checks passed.
- Coverage includes Android/iOS product grids, appearance persistence, large text, compact screens, keyboards, customer confirmation and admin forms/payments.
- Android device runtime testing was not performed during this release task.
- No backend deployment or schema change is needed for this update.

## Release notes

Improved product grids on Android and iOS phones.
Added quick access to Light, Dark and System appearance from the shop.
Improved layouts for large text, small screens and keyboards.
Polished login, notifications, order confirmation, admin products and payments.

## Rebuild

```sh
flutter build appbundle --release --no-pub --dart-define-from-file=env/prod.json
```

Local signing keys and release environment configuration remain excluded from Git.
