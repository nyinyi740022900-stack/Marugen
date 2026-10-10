# Android closed beta 1.0.1 (6)

Submitted on 2026-10-10 through Chrome's extension connection to Google Play Console.

- Package: `com.marugen.marugen_app`.
- Track: Closed testing — Alpha; rollout: 100% of the existing track.
- Release name: `1.0.1 (6) – UX and dark mode update`.
- Console status at submission: **Changes in review**. Google quick checks were still running. This is not confirmation of availability to testers.
- Managed publishing was already off; accepted changes publish automatically after approval.
- Uploaded bundle: `output/releases/marugen-1.0.1-6.aab` (ignored local artifact), 83,670,123 bytes.
- SHA-256: `b2b8731225039bfde78ca719d64187247d63b54fad1a0b47bb24fb4282f5cf50`.
- Build source: `6bc95f4`, with release version overrides matching `1.0.1+6` now recorded in pubspec.
- Signed release build succeeded; JAR signature verification succeeded; Play Console accepted version 6, API 24+, target SDK 36. No previously supported devices were removed.
- Flutter regression suite: 76 passed after the version update. Android device runtime testing was not performed during this release task.
- Evidence: `output/releases/closed-beta-1.0.1-review.jpg` (ignored local artifact).

## Backend compatibility

The linked project matched the release environment. Remote migrations 0001–0049 were already applied. Applied the additive 0050 customer remarks migration and deployed create-payment-intent v26 and send-order-notification v25. Both retained JWT verification. A read-only, zero-row query for customer_remarks and customer_remarks_revision returned HTTP 200. No payment/order transaction was performed.

## Release notes

Improved phone and tablet layouts with stable module navigation. Added dark mode and optional checkout remarks. Improved cart, order and delivery workflows, accessibility and error recovery.

## Rebuild

```sh
flutter build appbundle --release --no-pub --dart-define-from-file=env/prod.json
```

Use a new version code for the next Play upload; version code 6 is already used. Local signing keys and release environment configuration remain excluded from Git.
