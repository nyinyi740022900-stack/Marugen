# Closed beta 1.0.23 (28)

Submitted to Closed testing — Alpha for Google review on 2026-10-29, full rollout, replacing 27 (1.0.22). Built from main at 09a0a75 plus the version bump.

## Changes

- Push notifications ring: FCM messages carry sound and HIGH priority, and Android posts them on a new high-importance `order_updates` channel, so they ring and show a banner while the app is closed.
- Cancellation requested / approved / declined notices are pushed, not only written to the inbox.
- iOS gains the `aps-environment` entitlement and `remote-notification` background mode (needs a paid Apple team to sign).
- Promo codes are released when an order is refunded, not only cancelled, and matched by redemption row so renaming a code cannot leak its slot (migration 0069).
- Support contacts save immediately on add/edit/remove and accept phone numbers with spaces.

## Production backend

Deployed before submission: `send-order-notification`, `order-cancellation`, migration 0069 (its backfill freed the refunded `MARUGEN2026` redemption: 1 → 0). `FCM_SERVICE_ACCOUNT_JSON` is present in production secrets.

## Verification

- `flutter analyze`: no issues. Support suite: 14 passed.
- Deno: push message test and cancellation suites (9) passed; both functions type-check.
- Isolated PostgreSQL suite for 0069 (`supabase/tests/run_promo_release.sh`) passed.
- Not yet verified: a real Android device receiving a ringing push with the app closed.

## Release artifact

`output/releases/marugen-1.0.23-28-push-promo.aab`, 85.2 MB, `jar verified` (upload key). SHA-256: `e6e41ca9690d7064f1b2b4505683200835530d2f0c036411e11fccb695b1bf62`. Play Console: 0 devices lost versus 27.
