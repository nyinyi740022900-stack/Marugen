# EasyParcel pickup diagnostics — 22 October 2026

User approved an owner-facing explanation of pickup blockers and requested a live-account check. No top-up, paid shipment, cancellation or order reset is authorized by this implementation.

## Implemented locally

The Fulfillment pane includes a read-only “Check pickup & wallet” action and an EasyParcel All Parcels link. It separates explicit unpaid status, saved provider credit rejection, invalid details, scheduled pickup, overdue collection, hold, cancellation, return, collected, drop-off, delivered and unverified evidence. A zero wallet never becomes a causal explanation. Native SGD wallet/free-credit amounts are shown only when validated; other currencies are not relabelled or converted into an assumed available SGD balance. Failed refresh clears prior diagnostic output. Provider requests have a 12-second timeout.

New admin-only `easyparcel-pickup-diagnostics` reads wallet and the exact saved shipment (or exact AWB if no shipment ID exists). Shipment/AWB identity must match. Provider UTC collection dates are interpreted in Singapore. The diagnostic does not update order lifecycle, submit, pay or retry a shipment. Access tokens remain server-side.

EPSAMPLE identifiers are flagged as sample evidence, not proof of a live booking. The model marks them attention instead of awaiting pickup. Refresh/recovery controls that require a real AWB are suppressed for these orders. Booking results with sample identifiers remain needs-attention; verified tracking lookup rejects sample AWBs. No existing sample order is silently cleared or rebooked.

Explicit provider credit or parcel-detail rejection is persisted as an allowlisted `booking_issue:` marker in existing server-owned tracking detail, retaining the booking claim. Customer-facing order decoding replaces this internal marker with a general shop-checking message. No schema migration is needed. Settings explains that OAuth “Connected” alone does not prove the selected account is Live.

## Verification

Observed failing regressions before implementation: sample order was not attention; pickup explanation missing; sample controls incorrectly offered real-AWB actions; internal booking issue exposed in customer text; sample booking result incorrectly reported success. Backend diagnostic module tests initially failed because the implementation was absent.

Full production-configured Flutter suite: 249 passed before the last sample-control-only refinement; final delivery workflow suite: 16 passed including that refinement, narrow 390px phone/enlarged text and error recovery. Backend shipping/delivery/diagnostic tests: 44 passed. Edge functions type-check. Static analysis and diff checks are recorded in /private/tmp/pickup-analyze.log and the final execution outputs. Final phone preview: output/shipping-investigation/pickup-explanation.png. No real payment or pickup booking was performed.

## Live status and resume

Read-only portal investigation showed the Singapore account wallet and free credit at S$0.00 and NextGen All Parcels at zero orders for a date range covering the reported order. The reported app AWB starts EPSAMPLE. This suggests sample/account mismatch but does not conclusively identify the server token’s authorized account or the exact reason for non-collection.

Live verification and deployment are blocked on account access. `supabase db query --linked` returned HTTP 403 (insufficient privileges); the browser redirected the Marugen project URL to another accessible organization’s project list. No permission bypass or credential search was attempted. User was asked to sign in to the account that owns Marugen, and independently to use Owner Settings → Reconnect EasyParcel → select the Live Singapore account → Refresh. The browser Supabase tab is marked for handoff. Neither response has been received yet.

Not deployed; no new app build uploaded. Once proper access is available, inspect order 19102026-0001 and connection metadata, deploy the new diagnostic function plus updated easyparcel-book-shipment, easyparcel-refresh-status, easyparcel-reconcile-shipment and easyparcel-webhook (shared sample guards). Test owner/staff diagnostic success and customer/anonymous denial. Verify the explicitly selected Live account with read-only account/wallet/rate/shipment checks. Do not infer Live from SGD balance or absence of EPSAMPLE alone. Then build/release the app update using the existing production configuration. Keep the old claim until the actual existing shipment is reconciled; never use blind retry to test live shipping.

API reference inspected: https://easyparcel.github.io/OpenAPI/ — sandbox-and-live-environment, wallet-balance-2026-09, shipment-details-2026-09 and tracking status documentation. Diagnostic reads use 2026-09; existing booking remains on 2026-06.

## Live continuation completed through browser

The user selected the SGD Business account and completed OAuth at 2026-10-22 12:58:30 UTC (20:58 Singapore). The Supabase browser session now has Marugen access; the unrelated CLI token still returns 403 and was not bypassed. Through the authorized SQL Editor, pg_net performed read-only provider calls using the existing access token server-side, without revealing it. Wallet returned HTTP/API 200 with SGD balance 0 and free credit 0. Account information returned Marugen Fish Farm / Business. The old shipment ES-2610-CXZDP returned API 400: no order with that shipment number found in this account. A 0.5kg, weight-only quotation using the stored shop/destination postcodes returned 25 rates, all native SGD (minimum across all service types S$3.24; this is not a guaranteed door-pickup quote or a paid-order price). No booking/payment was submitted.

After verifying that mismatch, order 19102026-0001 was conditionally flagged needs_attention and its tracking text now states sample booking / live pickup not confirmed. The original AWB, shipment ID, paid amounts, stock and order status were preserved. Exactly one row changed. Existing claim was not cleared; no rebooking occurred.

Five edge functions deployed via the authorized Supabase browser editor: easyparcel-pickup-diagnostics, easyparcel-book-shipment, easyparcel-refresh-status, easyparcel-reconcile-shipment, easyparcel-webhook. Bundles were generated from the tested local source, with the Supabase SDK external import retained. No secrets embedded. Existing JWT settings preserved; the new diagnostic matches the existing booking function’s enabled legacy JWT gateway and validates the actual user and owner/staff role inside the handler. Diagnostic request without Authorization returned 401 / Missing Authorization header. Authenticated end-to-end owner button acceptance remains for the installed update.

Live evidence added an explicit safe not_found_in_account reason rather than discarding the provider’s account-mismatch result as a generic outage. New red/green regression: pickup-live-mismatch-red.log; final backend tests 45 passed. Updated diagnostic deployed after this change.

Signed production Android build 1.0.11 (16) created, jarsigner verified, all three native architecture binaries contain the configured live publishable key and omit the non-prod banner. Artifact metadata: output/releases/marugen-1.0.11-16-pickup-diagnostics.json. Uploaded to existing Alpha track, version 16 (1.0.11) validated; release saved and Publishing overview review submission in progress. Tester list/countries and production track unchanged. Version 15 (1.0.10) was observed already available to selected testers (released Oct 20 20:41).

Evidence screenshots: output/shipping-investigation/live-account-check-2026-10-22.png, live-sgd-quotes-2026-10-22.png, sample-order-attention-2026-10-22.png.

Live quote payload was read through the SQL result grid into output/shipping-investigation/live-quotes-2026-10-22.json (courier quotation data only, no addresses or tokens) and passed through the real normalizeRates implementation. Result: 25 native SGD services normalized; 18 door-to-door services; no FX lookup; every buyer/seller allocation sums to the provider total. Cheapest door-to-door in this one nonbinding 0.5kg check was Singapore Post Limited S$3.79, buyer S$1.89 / shop S$1.90. This does not change an existing order’s paid price or promise a future rate. Evidence: live-rate-validation.json.

The beta review confirmation was attempted, but Publishing overview still says Changes not yet submitted for review while automatic quick checks run. Submission activity has no new submission 16 yet. Do not claim accepted/in review until visibly verified. Current remaining quick-check estimate was up to 8 minutes.

## Final review submission handoff

Google quick checks completed with the page stating changes can now be sent for review. The final Send changes for review action repeatedly closed the confirmation without changing the not-submitted state; a full reload confirmed release 16 is still not submitted. No success claim is made. The confirmation is left open for a manual click. Screenshot: output/releases/closed-beta-1.0.11-review-handoff.png. Native Chrome coordinate fallback could not obtain an available window. Backend deployments and live read-only checks above remain complete; no real booking or payment was performed.
