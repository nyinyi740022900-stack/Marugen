# Payment repair rollout — 2026-10-20

**Production refund rollout completed on 2026-10-20 (Singapore time).**
The user approved the refund rollout and then withdrew the business-description
change. Description and industry were left unchanged. No real charges, refunds,
payouts, bank changes, or app-store releases were performed.

Migration 0059 and the three payment functions were deployed through the existing
authorized Supabase browser session because the CLI account returned HTTP 403.
Stripe's production destination now listens to the original three payment events
plus the four approved refund events (seven total).
## Prepared fixes

- Stripe refunds remain pending/requiring action/failed until Stripe confirms success.
- Verified refund records aggregate successful partial refunds; failed/pending amounts
  do not count as money returned. Only a full successful refund completes an order.
- Identity, customer, SGD currency and amount are checked against the original payment.
- Retrying a refund request reconciles existing Stripe refunds, including lost responses;
  it does not automatically retry failed or partial refunds. Further money movement
  requires a deliberate action in Stripe Dashboard.
- Status refresh uses `refresh_only: true` and cannot issue a refund.
- Newer Stripe observations win if concurrent requests finish out of order. Later bank
  returns can change succeeded refunds to failed/requiring action. Failed/canceled
  reservations are synchronized before their replacements.
- The existing service-only reconciliation function refreshes pending/requiring-action
  refunds without creating money movement and reports failures with HTTP 500.
- Customer/admin views and invoices distinguish refund states; a legacy terminal
  order with an incomplete verified refund is flagged for review without reopening
  fulfillment or inventory. Payment ledger collections exclude unpaid orders and
  subtract successful refunds.
- Android declares the Google Pay API metadata. This is local application configuration,
  not proof of Google production approval or a successful wallet payment.

## Production observations (read-only)

Account: Marugen Fish Farm; Supabase project `gexgcwdkbeythrnqmihe`.

- Live PayNow payment SGD 1.00 succeeded on 2026-10-19 at 20:15 Singapore time.
  Production webhook delivery succeeded. No new money movement was performed.
- Payments and payouts active; no active Stripe account tasks.
- Daily SGD automatic payouts to OCBC; first-payment funds shown available on
  2026-10-26. This is not a guaranteed bank-arrival date.
- Cards, PayNow and Link enabled. Google Pay disabled. Apple Pay enabled in the
  dashboard but the app has no merchant ID/Apple Pay entitlement or payment-sheet setup.
- Scalapay ineligible, Cartes Bancaires paused. Do not re-enable or misclassify the business.
- Reconciliation cron active every five minutes; orphan cleanup active every ten
  minutes. Both required Vault entry names exist. Recent cron runs succeeded.
- At inspection: zero pending orders and zero refunded orders. No historical
  refunded orders require correction in the inspected production database.
- Browser now has project access. CLI previously returned HTTP 403 under a different
  account; re-establish authorized deployment access without copying browser credentials.

## Approval package: refund repair

1. Apply **only** `0059_verified_async_refunds.sql` to production, after confirming
   columns/function/table do not already exist and saving the current schema/source snapshot.
   Register this exact migration in migration history using the authorized deployment
   process. Do not use an unqualified `db push`: unrelated delivery/shipping migrations
   0057/0058 and uncommitted work are present in this checkout.
2. Deploy `stripe-refund`, `stripe-webhook`, `reconcile-pending-orders`, including
   their `_shared` dependencies. Retain existing user-auth validation and webhook
   signature/service-secret validation. Webhook/reconciliation use `--no-verify-jwt`
   because they authenticate internally; never remove those internal checks.
3. Add these four subscriptions to **Marugen App Production**, destination
   `we_1UKzem1ABNEO8CQqR5xEnGZ9`, preserving its existing three payment events,
   URL, API version and signing secret:
   - `refund.created`
   - `refund.updated`
   - `refund.failed`
   - `charge.refunded`
4. Verify migration, deployed function versions and subscriptions read-only;
   unauthorized refund calls must be rejected, cron HTTP responses must succeed,
   and new webhook delivery failures must remain absent.
5. Publish a separately approved app release containing the refund display,
   ledger and Android wallet metadata fixes. The debug APK built locally is a
   compilation check, not a release artifact or an installed customer update.

No live charge, refund, payout or bank change is included in this approval package.
Test-mode end-to-end refund/webhook acceptance and signed-device card/3DS/PayNow/
wallet acceptance remain separate release checks; local regression tests are not
proof of those interactions.

## Business description and industry

The user withdrew the business-description change. Neither description nor industry
was edited. Do not apply the former proposal or change the category to bypass
Stripe eligibility. No support message was sent.

## Wallet prerequisites

**Google Pay:** app metadata is fixed locally and the existing PaymentSheet uses
SG/SGD with production mode derived from the live key. Confirm Google Pay & Wallet
Console production approval for the signed Android app, accept any required terms
through the account owner, obtain approval to enable it in Stripe, then test on a
physical Android device with a signed release build. A dashboard toggle alone is
insufficient. See https://docs.stripe.com/google-pay?platform=android.

**Apple Pay:** obtain the actual registered merchant ID, payment-processing
certificate and matching signed provisioning/Apple Pay entitlement from the
authorized Apple Developer account. Only then configure the merchant ID and
PaymentSheet Apple Pay parameters, rebuild, and test on an eligible physical iPhone.
No merchant identifier or entitlement is invented. See
https://docs.stripe.com/apple-pay?platform=ios.

**Scalapay/Cartes Bancaires:** Stripe determines eligibility; these are not app
bugs that can be repaired by enabling a toggle. Existing SGD card/PayNow/Link
checkout does not hard-code Scalapay. Other regional enabled methods remain
subject to currency, customer location, amount and mobile SDK support.

## Verification evidence

- `flutter test`: full suite and focused refund/large-text display tests.
- `flutter analyze`: final analysis log `/private/tmp/marugen-payment-final-analysis.log`.
- `flutter build apk --debug`: successful; merged manifest contains wallet API metadata.
- `deno test supabase/functions`: 46 passed; payment/refund subset 18 passed.
- `deno check`: refund, webhook and reconciliation entry points passed.
- `supabase/tests/run_stock_review_boundaries.sh`: temporary local PostgreSQL;
  refund, cancellation, idempotency, financial authorization and stock race checks passed.
- Combined shipping/delivery/refund migration checks are logged at
  `/private/tmp/marugen-combined-payment-checks.log`.
- Reviewer checked refund ordering, freshness, permissions, read-only refresh and
  historical display/revenue behavior; no remaining blocking findings.

These checks do not move real money or demonstrate native wallet/3DS interaction.
No dependencies were upgraded, no commits/pushes made, and existing unrelated
shipping/delivery changes were preserved.


## Completed production verification — 2026-10-20, 01:44 Singapore time

- Standalone migration `0059_verified_async_refunds` committed and registered in
  `supabase_migrations.schema_migrations`. Delivery/shipping migrations were not applied.
- Deployed `stripe-refund`, `stripe-webhook`, `reconcile-pending-orders` using bundles
  generated from the reviewed sources. Bundle/source hashes:
  `/private/tmp/marugen-payment-deploy/deployment-manifest.json`.
- Existing authentication settings retained: refund gateway JWT ON; webhook and
  reconciliation gateway JWT OFF with their internal signature/service-secret checks.
- Production schema: three new refund-summary columns; ledger RLS enabled;
  authenticated role cannot execute verified-refund RPC; service role can.
- Empty unauthenticated POST probes: refund 401, webhook 400 (missing signature),
  reconciliation 403. All rejected as expected after deployment.
- Authorized recovery was queued only after confirming no pending payments/refunds.
  Response at 2026-10-20 01:44:16 Singapore time: HTTP 200,
  `{"checked":0,"reconciled":0,"refundsReconciled":0,"failures":0}`.
- Before/after order status counts unchanged: paid 1, packing 1, shipped 2,
  cancelled 7, delivered 7. Refund ledger remains empty; no money was moved.
- Stripe destination `we_1UKzem1ABNEO8CQqR5xEnGZ9` active with seven verified event
  subscriptions. Endpoint URL, API version and signing secret retained.
- Source backups and a targeted production schema snapshot saved under
  `/private/tmp/marugen-payment-deploy/`; no full managed database backup created.
- Screenshots: `/private/tmp/marugen-payment-webhook-after.png`,
  `/private/tmp/marugen-payment-recovery-verified.png`,
  `/private/tmp/marugen-payment-migration-applied.png`.

Customer app UI/revenue fixes still require a separately approved app release.
Wallet production approvals/device acceptance remain open; no unsupported payment
method was reactivated. A live charge/refund end-to-end test was not performed.
