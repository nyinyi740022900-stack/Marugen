# Closed beta 1.0.27 (32)

Built 2026-11-08 from `codex/whole-app-audit-fixes` (PR #3, not yet merged to main) at e6c1911 plus the version bump, for Closed testing — Alpha. Upload and submission are done by the owner in Play Console (the bundle is too large for the Chrome extension).

- Release name: `1.0.27 (32) – Smoother shop and order fixes`.
- Release notes (en-US): "Smoother product photos (swipe down to close), clearer option buttons, faster wishlist hearts, finish payment on pending orders, reviews after delivery, and many fixes."

## Changes

Everything in PR #3:

- Address and price validation, pending orders can resume payment, push opens the order and device tokens stay on one account.
- Smaller photos, stale stock refresh, Android back goes home; dashboard and analytics totals counted on the server.
- Shop UX polish, contact options, iOS permission copy, reviews after delivery, safer carts, order tabs and account settings.
- Apple design review (e6c1911): photo gallery grows from the product photo and closes with a swipe; haptics on cart, wishlist, option chips and paid orders; touch-down press feedback on iOS; "Select Options" is the primary button until options are chosen; iOS optical font sizes and tracking; translucent iOS tab bar; native iOS alerts and pull-to-refresh; interruptible wishlist heart with a pop.

## Production backend

Requires migrations 0072–0075 and the deployed Edge Functions resume-order-payment, create-payment-intent, send-order-notification and order-cancellation. The owner confirmed on 2026-11-08 that all of these are applied in production; the Supabase CLI here returned 403 for the project, so this was not verified from this machine.

## Verification

- `flutter analyze`: no issues. `flutter test`: 541 passed, 4 skipped.
- iPhone 17 simulator (debug, local `.env`): product detail option buttons, gallery Hero open, spring back and flick-to-close, header following the gallery page, translucent tab bar with the last grid row clear of it. No Flutter errors in the run log.
- Not checked on a device: haptics, press-scale feel, wishlist pop and iOS alerts (need a login).

## Release artifact

`output/releases/marugen-1.0.27-32-apple-design.aab`, 85.6 MB (85,586,010 bytes), `jar verified` (upload key CN=Marugen Koi Farm). versionName 1.0.27, versionCode 32, built with `flutter build appbundle --release --dart-define-from-file=env/prod.json` (live Stripe publishable key, production Supabase). SHA-256: `cb9825af1468f52482b8a806b03d7ae1fb520d66545fb010e0a4cd8a7d7847e4`.
