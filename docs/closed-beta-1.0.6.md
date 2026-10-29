# Android closed beta 1.0.6 (11)

Prepared 2026-10-20 (Asia/Singapore) for the existing **Closed testing — Alpha** track. The user explicitly requested the closed-beta rollout. Upload/submission status is updated below after Play Console verification.

## Release

- App: Marugen, package `com.marugen.marugen_app`.
- Bundle: `output/releases/marugen-1.0.6-11-shipping.aab`.
- SHA-256: `730094377a69fbf50bd1f4546f2aa46e93ba1a5ac59c961a65352b6cea7c6a26`.
- Existing Marugen upload certificate verified. VersionCode 11; versionName 1.0.6. Production client configuration; payments are live, not automatically sandboxed by the closed-testing track.
- Existing Alpha tester Google Group, feedback destination and 178-country configuration retained. No invitations or messages sent. At inspection, the dashboard showed 6 opted-in testers.

## Changes

SGD shipping quotes and immutable buyer/shop contributions; TracX-only courier services; trusted SKU kg × quantity; buyer-free shop delivery for live-fish/mixed baskets; booking and tracking safeguards; payment recovery and verified refund status display. Shipping backend rollout and weight evidence: `supabase/SHIPPING_DEPLOYMENT.md`. Refund rollout evidence: `supabase/PAYMENT_DEPLOYMENT.md`.

## Verification

- 236 Flutter tests passed; static analysis clean.
- 54 server tests passed. Shipping/database/refund compatibility and production rejection/permissions checks passed.
- Signed production APK and AAB builds passed; signatures verified; APK manifest confirms 1.0.6+11. Bundled client configuration contains no detected server-only credential names/prefixes.
- No physical Android device connected. Live interactive checkout, wallet/3DS and paid shipment acceptance remain unverified. No real charges, refunds, top-ups or bookings were created during this beta task.

## Release notes (en-US)

Shipping fees now display in SGD with clear buyer and shop contributions. TracX Logis is the only courier, with fees based on item weights and quantities. Live-fish shop delivery is free for buyers. Improved delivery tracking, booking safeguards, checkout recovery and refund status.

## Submission status

Submitted on **2026-10-20 (Asia/Singapore)**. Play Console accepted 11 (1.0.6), API 24+, target SDK 36, mapping/native debug symbols and showed **Ready to release**. Preview showed zero lost supported devices. Saved 100% rollout within the existing closed Alpha track, without including old version 10.

Publishing overview contained exactly one pending change: **Closed testing — Alpha, 11 (1.0.6), Start full rollout**. Sent this change for review. The final visible status is **Changes in review**, with that exact track/version listed. Managed publishing remains off, so approval publishes the closed-track update automatically. Google approval and availability of 1.0.6 to testers are not yet confirmed. No Production release was submitted.

Evidence: `output/releases/closed-beta-1.0.6-in-review.png` and corresponding `.txt`; upload/preview evidence is saved beside them. Native Chrome accessibility controls were used after extension browser inventory timed out. The exact verified bundle was selected using the normal file picker.

Tester opt-in URL: https://play.google.com/apps/testing/com.marugen.marugen_app
