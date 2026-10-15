# Android closed beta 1.0.4 (9)

Prepared 2026-10-16 for the existing Closed testing — Alpha track.

## Changes

- Consistent guest Profile/Orders login layouts and account-scoped address, notification and order data.
- Clearer checkout/order recovery, verified cancellation, and checkout idempotency to prevent duplicate reservations/charges after response loss.
- Server-owned payment/refund records: admin fulfillment remains available; direct financial state/amount forgery is denied. No new Staff/Owner product feature or production account was introduced.
- Admin navigation animation, dashboard touch feedback, remote image fallbacks, responsive analytics and animated Light/Dark button typography fixes.
- Android MainActivity now extends FlutterFragmentActivity so the native Stripe SDK initializes successfully.

## Verification

Fresh release checks: 193 Flutter tests passed; analyzer clean. Prior native Android owner/admin and existing internal staff-role fixtures passed against an isolated backend. Real local Auth/REST/Edge/DB, Stripe test mode, network-loss recovery, webhook replay, refunds and concurrent stock reservation checks passed. Exact scope and logs: `audit-fixes-verification-2026-10-15.md`.

Real Google sign-in, interactive card-form/cancel, Google Pay/3DS, external redirects, physical-device accessibility and courier booking remain beta acceptance work. Passing SDK confirmation does not prove those interactions.

## Backend rollout

User authorized commit/push and closed-beta upload on 2026-10-16. Read-only preflight found zero duplicate non-cancelled checkout key groups. Dry run contained only migrations 0052–0055. Applied those migrations to the existing linked project `gexgcwdkbeythrnqmihe`, then deployed create-payment-intent, cancel-order, stripe-webhook and reconcile-pending-orders. Server-authenticated webhook/reconciliation retain their required no-gateway-JWT setting and validate Stripe signatures/service credentials in their handlers.

Post-deployment checks confirm latest migration 0055, both payment guards, stronger checkout unique index and enabled order RLS. No real payment, refund, shipment or customer fixture was created for production smoke testing.

## Build/configuration

Version 1.0.4+9. Build uses the same `env/prod.json` production client configuration as beta 1.0.3. It contains a **Stripe live publishable key**; closed testing does not automatically sandbox payments. Do not use this build for assumed-free card tests. The successful Stripe sandbox acceptance used a separate isolated environment. Server credentials are not bundled; ignored client config is not committed.

## Submission status

Signed bundle built successfully: `output/releases/marugen-1.0.4-9.aab` (83.8 MB build report). JAR signature verification passed. Upload certificate SHA-1 matches the registered prior beta: `7E:9F:18:20:EC:82:F1:D8:47:35:F2:76:A9:7D:8F:84:4B:12:BC:17`.

SHA-256: `07d536214514003f7f7447b46c250b10389c7907c819f64aa678d9e7a34d4101`.

Deployed rejection smoke checks passed: create-payment-intent/cancel-order return 401 to an anonymous caller, reconciliation returns 403, unsigned Stripe webhook returns 400. Evidence: ignored `output/releases/beta-1.0.4-deployed-smoke.json`.

Source release commit `45c1090` was pushed to `origin/codex/whole-app-audit-fixes`. Main was not changed.

After reconnect, extension browser APIs still failed to load their request-header policy. Continued using the supported native Chrome accessibility controls. Uploaded the exact signed bundle through the normal file picker; Play accepted version **9 (1.0.4)** with mapping/native debug symbols, minimum API 24 and target SDK 36. Preview reported Ready to release and no loss of supported devices.

Saved the release in **Closed testing — Alpha**, retaining its existing tester/country configuration and 100% rollout within that closed track. Submitted the single release change. Publishing overview visibly confirmed **Changes in review** and **1 change sent for review**. Google's quick checks were still running (up to 14 minutes shown); approval and availability to testers are not yet confirmed. Managed publishing remains off. No Production release was submitted.

Evidence: ignored local screenshot `output/releases/closed-beta-1.0.4-in-review.png`.
