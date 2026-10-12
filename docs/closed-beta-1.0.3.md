# Android closed beta 1.0.3 (8)

Prepared on 2026-10-12 for the existing Closed testing — Alpha track.

## Changes

- Moved appearance access from Shop to the upper-right Profile toolbar, available to guests and signed-in customers.
- Removed Profile's Appearance row and guest “THIS DEVICE” section.
- Kept English app copy and existing persisted Light/Dark/System preferences.

## Google sign-in diagnosis and configuration

The native Android sign-in implementation supplies the configured web OAuth client ID. The production client project is `884533098044` (`gen-lang-client-0132496698`). Its OAuth audience was already **External / In production**, so a Google test-user allowlist is not the restriction.

Compared the Play Console's downloaded public certificate ZIP with existing Google Android OAuth registrations:

- Existing hybrid classical signing SHA-1: `05:6C:23:47:CF:C8:F5:7C:09:15:DD:6E:01:D9:A2:45:21:0D:F1:50` — already registered.
- Current Play deployment signing SHA-1: `45:C4:C2:EC:10:DB:D4:00:F1:A1:BD:1D:62:2C:0F:07:C7:07:52:B6` — missing; registered for the same package `com.marugen.marugen_app`.
- New public client: `884533098044-mbgnkieic87jvcv89pi7ljnjo1rsja9k.apps.googleusercontent.com`, named `Marugen Android (Play deployment signing)`.
- Upload signing SHA-1: `7E:9F:18:20:EC:82:F1:D8:47:35:F2:76:A9:7D:8F:84:4B:12:BC:17` — already registered as `Marugen Android`.

No existing client was deleted or replaced, and no scopes, privileges, audience, client secrets or backend configuration were changed. Google indicates configuration propagation can take 5 minutes to a few hours. This corrects a verified signing mismatch; a successful Google login from the newly Play-signed build remains a separate end-to-end check.

Evidence: `output/releases/google-play-signing-fixed.png` (ignored local artifact).

The plugin documents that signing/client configuration errors can appear as “canceled” after choosing an account: [Google Sign-In Android troubleshooting](https://pub.dev/packages/google_sign_in_android#troubleshooting).

## Validation

- 133 Flutter tests passed; analyzer reported no issues. Profile toolbar and preference tests cover guests and signed-in customer fixtures on Android and iOS.
- iPhone simulator build succeeded before the user redirected runtime verification to Android.
- Android Pixel 7 emulator UI smoke test passed against the actual app/router: Profile toolbar control, removal of the device section, Dark across Profile/Shop, Light selection, and a hittable Google login button. This test uses the normal debug instrumentation build and production backend reads, bypassing production crash/push startup services so test failures remain visible. It does not submit Google credentials or establish a Google session.
- Android runtime test dismissed the server-managed promotion modal before using navigation. Missed taps are fatal, and failures are reported to the test runner.
- Android evidence captured and visually reviewed: `output/releases/android-profile-light.png`, `android-profile-dark.png`, `android-shop.png`, and `android-login.png` (ignored local artifacts).
- Submission details are recorded below once completed.

## Release notes

Moved Light, Dark and System appearance settings to the top-right corner of Profile.
Simplified Profile by removing the device appearance section.
Corrected Google sign-in configuration for Play Store builds.

## Rebuild

```sh
flutter build appbundle --release --no-pub --dart-define-from-file=env/prod.json
```
