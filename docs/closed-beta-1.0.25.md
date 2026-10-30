# Closed beta 1.0.25 (30)

Submitted to Closed testing — Alpha for Google review on 2026-10-30, full rollout, replacing 29 (1.0.24), which was available to testers. Built from `codex/whole-app-audit-fixes` at 4c7a09d plus the version bump. Publishing overview shows **Changes in review** (quick checks still running at submission; approval and tester availability not yet confirmed).

- Release name: `1.0.25 (30) – Private promo codes and local times`.
- Release notes (en-US): "Dates and times now show in Singapore time. Promo codes are checked more securely, and a code you already used is flagged when you apply it."

## Changes

- Promo codes are private: customers check one exact code through `check_promo_code` instead of reading the `promo_codes` table, wildcards no longer match, and a code the customer already used is flagged when applied.
- Order, invoice, notification, review and admin times show device-local (Singapore) time instead of UTC.
- A promo expiry date lasts until the end of that local day (previously 08:00 SGT on that day).

## Production backend

- Migration 0071 applied by the owner. Read-only probe with the public client key: anonymous `promo_codes` listing returns 0 rows; `check_promo_code` and `find_promo_code` exist and deny anonymous callers (HTTP 401, 42501).
- Deployed with the Supabase CLI from 4c7a09d (`--use-api`, clean `supabase/functions`): `create-payment-intent` 29 → 30 and `checkout-shipping-quote` 5 → 6, both ACTIVE with `verify_jwt` unchanged (true). CORS preflight returns the handler's `ok` (boot check); unauthenticated POST is rejected (401).
- Not yet verified: a signed-in checkout applying a real promo code against production.

## Verification

- `flutter analyze`: no issues. Flutter: 504 passed; the 4 failures are the print acceptance tests that need `pdftoppm` and local `output/` PDFs.
- Deno: 104 passed; both functions type-check. SQL: `run_private_promo_codes.sh` and `run_promo_release.sh` passed.

## Release artifact

`output/releases/marugen-1.0.25-30-private-promo-local-time.aab`, 85.2 MB (85,242,153 bytes), `jar verified` (upload key CN=Marugen Koi Farm). Merged manifest: versionCode 30, versionName 1.0.25; the live Stripe publishable key and production Supabase project are compiled in from `env/prod.json`. SHA-256: `deec1a588e575407986cff6e6cd9abd2b44a26b4cbc1a3f516a294f0d8e4fde9`. Play Console: 30 (1.0.25), API 24+, target SDK 36, Ready to release, 0 devices lost, 19.2 MB for new installs.

The bundle was dragged into Play Console by the owner (the Chrome extension cannot upload files this large). The Chrome Supabase session belongs to a different account (YaPi organization) without access to the Marugen project, so the functions were deployed with the CLI.
