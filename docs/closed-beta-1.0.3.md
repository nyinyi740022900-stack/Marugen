# Android closed beta 1.0.3 (8)

Prepared on 2026-10-13 for the existing Closed testing — Alpha track.

## Changes

- Moved appearance access from Shop to the upper-right Profile toolbar, available to guests and signed-in customers.
- Removed Profile's Appearance row and guest “THIS DEVICE” section.
- Kept English app copy and existing persisted Light/Dark/System preferences.
- Replaced in-app placeholder privacy text with the approved contact email, full data handling/retention information and request links; login now exposes Privacy Policy before sign-in.
- Deletion now removes customer authentication and personal avatar objects, while retaining necessary business records with detached customer references. Applied migration 0051 and deployed delete-account/send-order-notification in the existing Supabase project.

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

- 135 Flutter tests passed; analyzer reported no issues. Profile toolbar and preference tests cover guests and signed-in customer fixtures on Android and iOS.
- iPhone simulator build succeeded before the user redirected runtime verification to Android.
- Android Pixel 7 emulator UI smoke test passed against the actual app/router: Profile toolbar control, removal of the device section, Dark across Profile/Shop, Light selection, and a hittable Google login button. This test uses the normal debug instrumentation build and production backend reads, bypassing production crash/push startup services so test failures remain visible. It does not submit Google credentials or establish a Google session.
- Android runtime test dismissed the server-managed promotion modal before using navigation. Missed taps are fatal, and failures are reported to the test runner.
- Android evidence captured and visually reviewed: `output/releases/android-profile-light.png`, `android-profile-dark.png`, `android-shop.png`, and `android-login.png` (ignored local artifacts).
- Three Deno deletion tests passed. A live database check used disposable transaction-only fixtures and ROLLBACK: auth/profile/address rows were removed, while orders, promo counts, status audit and EasyParcel records remained with detached user references. No real customer was deleted.
- Android runtime evidence includes android-privacy-policy.png. Full Google credential sign-in and a signed-in HTTP deletion flow remain separate checks.
- The public website still has its prior policy. The user explicitly requested proceeding with the existing links after consulting the tester team; no website deployment or Google policy approval is claimed.
- Submission details are recorded below once completed.

## Release notes

Moved Light, Dark and System appearance settings to the top-right corner of Profile.
Simplified Profile by removing the device appearance section.
Corrected Google sign-in configuration for Play Store builds.

## Rebuild

```sh
flutter build appbundle --release --dart-define-from-file=env/prod.json
```

After an on-device integration build, allow Flutter's normal release tooling regeneration. With `--no-pub`, the prior debug plugin registrant retained the integration test plugin while Gradle correctly excluded that dev-only plugin from release, causing a compilation error. Building without that flag regenerated the release registrant and succeeded; the test plugin was excluded.

## Signed artifact

- File: `output/releases/marugen-1.0.3-8.aab`
- Size: 83,688,534 bytes
- SHA-256: `d5f8dc9783cc65061c3f9c919dc7ab94099d8020de11be578b1e4ed8b4b34d30`
- Signature verification: jar verified.

## Play Console preparation

Uploaded the verified bundle to the existing Alpha draft on 2026-10-13. Preview reported Ready to release, 100% rollout to the Alpha test audience, and zero lost phone/tablet support. Publishing overview also contained existing tester-group, privacy URL and Data safety changes prepared separately. Reviewed those pending items and added the missing App interactions declaration for actual app visits/product views: collected, retained (not ephemeral), required, Analytics purpose. Existing website URLs were retained at the user's explicit instruction.
