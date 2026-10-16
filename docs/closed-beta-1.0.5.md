# Android closed beta 1.0.5 (10)

Prepared 2026-10-16 for the existing Closed testing — Alpha track. **Not uploaded yet.**

## Changes since 1.0.4 (9)

- Startup: removed the `runZonedGuarded` wrapper that raised a Flutter "Zone mismatch" error on every launch. Uncaught errors still reach Crashlytics through `PlatformDispatcher.onError`.
- Notifications: the OS permission prompt now appears after the promo popup is closed (or skipped), instead of stacking on top of it on first launch. The admin shell asks after its first paint.
- Login: visible back button when Login is pushed (Buy Now, Profile). Readable status-bar icons on its light background. The status-bar helper sets only status-bar fields, so the Android navigation bar is unchanged.
- Guide: Varieties / Care Guides / Services tabs are equal width on phone and tablet (regressed in 6bc95f4).
- Admin: raw `Error: $e` text in 12 screens replaced with plain-language messages (`friendlyErrorMessage`); load failures offer Retry.
- Local native acceptance tests now also run on iOS simulators.

## Verification

- `flutter analyze`: no issues. Unit tests pass except `packing_label_test`, which needs `pdfinfo` (poppler) and is not installed on this machine. Packing-label code is unchanged since 1.0.4.
- Android Pixel 7 emulator: guest integration test passed (shop, guest orders, profile light/dark, login back button, privacy policy).
- iOS simulators, local Supabase + Stripe test mode: iPhone 17 customer checkout (native SDK → webhook → paid, stock −1); owner admin on iPhone 17; staff admin on iPad Air 11"; dark mode; iPad landscape shop layout.
- iPhone 17 manual: promo → notification order, full-screen gallery and Login status bar, Login back.
- Release manifest contains `POST_NOTIFICATIONS`.

Not covered: interactive PaymentSheet card entry, 3DS, Google/Apple Pay, real Google/Apple sign-in, physical-device accessibility, courier booking.

## Build

Version 1.0.5+10, built with `env/prod.json` (same production client config as 1.0.3/1.0.4). It contains the **Stripe live publishable key**, so card payments by testers are real charges.

- Bundle: `output/releases/marugen-1.0.5-10.aab` (83.8 MB)
- SHA-256: `cee6cb972bca9e683c3e020c05537efb7ed8f8e74ae042ab496f8ae45e26fc9c`
- `jarsigner -verify`: jar verified (same 1049 protobuf-entry warnings as the accepted 1.0.4 bundle)
- Upload certificate SHA-1: `7E:9F:18:20:EC:82:F1:D8:47:35:F2:76:A9:7D:8F:84:4B:12:BC:17` (matches prior betas)

No backend migration or Edge Function change is required for this release.
