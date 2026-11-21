# Closed beta 1.0.28 (33)

Built 2026-11-19 from `codex/whole-app-audit-fixes` at 4d76192 plus the version bump, for Closed testing — Alpha. Not uploaded yet (as of 2026-11-21): the owner drags the bundle into Play Console (too large for the Chrome extension).

- Release name: `1.0.28 (33) – Safer checkout, feedback and home banners`.
- Release notes (en-US): "Checkout no longer resets while you pay, clearer payment confirmation, Send feedback and app version in Profile, help for guests, email confirmation with resend, home banners, fish video in the photo gallery, and many fixes."

## Changes

Everything since 1.0.27 (commits c65bec4, a035205, 4d76192), from the 18 Nov three-role review:

- Checkout survives an auth token refresh; a slow payment confirmation shows "Payment received. We're confirming it with the bank" and clears the cart only once paid; a changed total can be paid on the second tap.
- Order detail always refetches; reorder reports what was skipped; notification permission is asked after the first order instead of at launch.
- Profile: Send feedback, app version, and FAQ / Terms / Privacy for guests. Sign-up shows "Confirm your email" with resend.
- Home banners: link picker, no layout jump, refresh on pull and resume. The daily promo popup is retired.
- Live fish: free hand-delivery promise, "this exact fish" line, video as a gallery slide, age and certificate photo.
- One contact picker from product page, product card and Services.
- Admin: Payments merged into Orders (payment line on each card, copyable Stripe id), "Collected through Stripe" on Home, bounded dashboard queries, guarded write buttons, unsaved-changes guard notices text edits, product editor no longer wipes fish gender.

## Production backend

Rolled out to production (gexgcwdkbeythrnqmihe) on 2026-11-21 by Claude, after the owner re-logged the Supabase CLI:

- Backup first: `supabase db dump --linked` (schema + data) to `output/backups/2026-11-21-pre-0077/`. Restore drill passed: repo schema 0001–0076 on a throwaway local Postgres, production public data loaded (6 profiles, 20 products, 48 variants, 5 orders, 7 order items, 4 refunds), then 0077–0080 each applied twice on that data without error.
- Pre-flight clean: tables/functions owned by postgres, cron jobs run as postgres, both Vault secrets present, pg_net answers all 200, bucket holds 139 JPEGs (largest 2.5 MB), and every production function body matches the repo except `handle_new_user()` (not replaced by these migrations). `order_number_counters` already had RLS on in production.
- Migrations 0077, 0078, 0079, 0080 applied in order with `supabase db query --linked -f`. Verified: RLS on `order_number_counters` and `order_stock_restorations`; anon/authenticated cannot execute the four server-only RPCs; bucket limit 10 MB; 3 GST columns; 9 indexes; `admin_payments_summary`, `admin_top_products`, `release_easyparcel_token_refresh`, `admin_ops_health` exist; cron job `ops-monitor` every 15 minutes; `ops_monitor_findings()` returns nothing.
- All 23 live `verify_jwt` values matched `supabase/config.toml` before deploying. 22 Edge Functions deployed with `--use-api` (all except `easyparcel-status`): create-payment-intent v32, stripe-webhook v21, easyparcel-webhook v14 and the rest; all ACTIVE, the same five still have JWT off.
- After deploy: unauthenticated POST returns 401 (create-payment-intent, order-parcels), 400 (stripe-webhook, no signature), 403 (easyparcel-webhook, reconcile-pending-orders); the 14:20 UTC reconcile cron run answered 200 and its request id was recorded.
- Not exercised end to end: a real checkout through the new create-payment-intent (live Stripe), a refund restoring stock, an EasyParcel booking, and the EasyParcel webhook source-IP log (needs one real delivery).

## Verification

- `flutter analyze`: no issues. `flutter test`: 754 passed, 4 skipped.
- `deno test supabase/functions`: 151 passed. SQL suites `run_sprint1_security_fixes.sh`, `run_sprint3_hardening.sh`, `run_sprint4_leftovers.sh`: all pass on a local Postgres with 0001–0079.
- Pixel 7 emulator, release APK of the same commit, production backend after the rollout: cold start shows the catalogue with no popup, no permission prompt and no banner gap; guest Profile shows FAQ & Support, Send feedback, Terms, Privacy and "Version 1.0.28 (33)"; a product page opens with options. No Flutter or runtime errors in logcat.
- Not checked: sign-in, checkout and payment (live Stripe key), admin screens, iOS, a real device.

## Release artifact

`output/releases/marugen-1.0.28-33.aab`, 86.9 MB (86,864,952 bytes), `jar verified` (upload key CN=Marugen Koi Farm). versionName 1.0.28, versionCode 33, built with `flutter build appbundle --release --dart-define-from-file=env/prod.json`. SHA-256: `2181ccc9030908f026f2231ea067db029ab1e3834ceb6499c3db550849ae2ae2`.

## Message for testers (paste into the tester chat group)

> Hi everyone — Marugen 1.0.28 is out on the test track. Please update from Play Store, then over the next 14 days:
>
> 1. Open the app at least once a day and browse a few fish and products.
> 2. Try one thing each day: search, add to cart, wishlist, sign up / log in, read a care guide, open FAQ.
> 3. Tell us what you think from inside the app: **Profile → Send feedback**. It opens WhatsApp or email with the app version already filled in. Even one line helps ("photo was slow", "couldn't find X").
> 4. If something breaks, send a screenshot through the same Send feedback button.
>
> Please keep the app installed until 3 December. Thank you!
