# Audit Findings Fix Plan

Approved scope: findings 1–7 in `docs/whole-app-audit-2026-10-14.md`. Execute in this checkout on `codex/whole-app-audit-fixes`, preserving earlier guest UI work.

- [x] Payment: failed events remain retryable; verify authoritative Stripe state, PI/order/amount/currency; cancellation is server owned and cannot release paid stock; tests for event ordering/retry/mismatch/idempotency.
- [x] Account isolation: user-scoped address data and owner validation; generation-safe notifications and targeted rollback; regressions across logout/account switching.
- [x] SQL boundaries: revoke customer order/item insertion; positive quantity/product/variant validation; protect review admin fields on insert/update; isolated database regressions.
- [x] Detail/UI: authoritative order refresh scoped to identity; adaptive analytics text/labels with real screen regressions.
- [x] Review each task, then broad review. Run full Flutter/Deno checks; document native/backend acceptance and deployment dependencies.

Ruling: User approved starting the audit recommendations; no repeat design approval is necessary. Development and local tests are authorized; live charges, production migrations/function deployment and beta upload are separate release work.
Ruling: Preserve dirty checkout on a new local branch. A new worktree would omit the existing shared UI changes under review.
Ruling: SQL source changes are not a claim that production permissions changed. Package migrations and tests, and record deployment sequencing.

## Status — 2026-10-14

Findings 1–7 are implemented in source with regressions. Verified locally: `flutter analyze` no issues; Flutter 178 passed, 1 failed (`packing_label_test` needs `pdfinfo`/poppler on this machine, unrelated); Deno payment lifecycle 5/5; isolated PostgreSQL boundaries 21/21 plus verified payment cancellation checks (run with `LANG=en_US.UTF-8`).

Follow-up review fixes: analyzer warnings in checkout/order detail, import order, and an error message for the admin dashboard "Cancel now" action when the server refuses cancellation.

Still open: independent broad review; Stripe sandbox and Android device acceptance; deploy order — migrations 0052→0053, then `cancel-order`, `stripe-webhook`, `reconcile-pending-orders`, `create-payment-intent` functions, before shipping the app build that calls `cancel-order`.

## Handoff verification — 2026-10-15

Claude's changes were preserved; no commit was created. HEAD remains 2a7c595 on codex/whole-app-audit-fixes.

Fresh checks:
- Flutter: 179 passed, no failures (including packing label/PDF test, now available).
- Flutter analyzer: no issues found.
- Deno: 12 passed (payment lifecycle/remarks/deletion helpers).
- Disposable local PostgreSQL runner: passed stock/review and verified cancellation checks.

Completion decision:
- Account isolation: implemented and locally verified.
- Order Detail/Analytics: implemented and locally verified, including stale refresh preview and retained cancellation dialog regressions.
- Stock/review migration 0052: implemented and isolated-DB tests pass; not deployed.
- Payment/0053: PARTIAL. Earlier checked payment/SQL boxes mean implementation exists, not release acceptance. Four review blockers remain in current source:
  1. 0053 only guards status changes. Staff/owner can clear stripe_payment_intent_id first, then cancel/cron can release linked payment stock. Protect link changes and test the two-step bypass.
  2. create-payment-intent link-error cleanup swallows Stripe cancellation failure and still cancels the pending DB order. Never release stock without confirmed cancellation; test committed link + lost response + processing/succeeded Stripe state.
  3. create-payment-intent idempotency lookup/index only covers pending. Retrying after the original becomes paid can create another payable order. Preserve checkout identity through completed states and test paid retries/concurrency.
  4. Checkout confirmation fetch errors escape into generic retry UI. Keep the known order destination and prevent another payment attempt after sheet success; test transient lookup failure.

Next sequence: fix blockers 1–3 with backend/SQL regressions, fix blocker 4 with client regression, perform independent broad review, rerun all checks, then Android/Stripe sandbox acceptance. Decide production deployment/build/upload separately. Do not commit/push or publish during handoff verification.

## Remaining blockers resolved — 2026-10-15

- PaymentIntent links are immutable after assignment; untrusted roles cannot assign/clear/reassign them before cancellation. Actual-policy regression verifies the two-step bypass is denied.
- Link-error cleanup releases stock only after Stripe cancellation confirmation and a fresh order/link check; refusal/unknown state preserves the reservation.
- Checkout keys remain unique through paid/fulfilled/refunded states. The endpoint returns the completed order, and the client skips native payment initialization/presentation. Historical duplicate migration preflight fails without modifying orders.
- Confirmation lookup errors are retried within a bounded window; unresolved confirmation routes to the known order and preserves the cart. Ownership is checked around asynchronous reads.
- An additional review race is closed: item insertion locks its pending parent before stock mutation. Two real PostgreSQL sessions verify both insertion/cancellation orderings and exact restoration.

Fresh verification: Flutter 189 tests passed; analyzer no issues; Deno 16 tests passed; four payment Edge Functions type-check successfully. Final local PostgreSQL runner passes 23 stock/review assertions, cancellation/link checks, persistent idempotency/historical preservation checks, and the two-session reservation race.

Scoped account/UI/SQL/payment reviews are clean after fixes. Broad final review is recorded in `docs/audit-fixes-verification-2026-10-15.md`. No commit, push, production migration/function deployment, or beta upload has been performed.

Release gates remain external: Android runtime (no Android device/system image available), Stripe sandbox/network/webhook testing, deployed schema/configuration verification. Deployment dependencies: verify historical duplicate preflight; apply 0052→0053→0054; deploy cancel-order/stripe-webhook/reconcile-pending-orders/create-payment-intent before releasing the app that calls the new contracts. Test on staging before production.


## Native acceptance and deployed preflight — 2026-10-15

Android guest integration passed on Pixel_7 (API 37.1 / 16 KB): two-column shop screenshot, matching Orders/Profile guest login position, Profile appearance control, both themes, Google login button reachability and privacy contact. Supabase writes are blocked by a test-only client; this is not signed-in/OAuth/payment acceptance. Full Flutter suite now 190 passed; analyzer clean.

Read-only production checks show migration 0051 is latest, zero duplicate non-cancelled checkout-key groups, orders RLS enabled, and both stale cleanup/reconciliation cron schedules active. Migrations 0052–0054 remain undeployed. Stripe CLI refresh completed. Provider-only test-mode create/retry, cancel, successful payment and full refund passed; this does not cover app checkout/webhook/stock integration. The deployed function inventory is missing cancel-order. No commit/push/deploy/upload.


## Continued acceptance — Android Stripe blocker fixed

- Reproduced native Stripe initialization failure: MainActivity was FlutterActivity. Corrected it to FlutterFragmentActivity; the native initialization target passed afterward.
- Re-ran Android guest UI/theme regression target after the native change: passed. Analyzer clean.
- Applied all migrations through 0054 to an isolated local Supabase stack. Fixed only its VM source-mount path (public test sources now under gitignored output/local-acceptance, server credentials in private temp files).
- Real local Auth/REST/Edge/DB + Stripe sandbox acceptance: 13 checks passed, including replay/order/idempotency/refund/concurrent single-fish reservation.
- Android checkout totals/reachable CTA + native SDK confirmation + actual forwarded Stripe webhook + paid order detail/exact-once stock decrement: passed. This uses the SDK synthetic payment-method API and does not claim interactive native form/Google Pay/3DS coverage.
- Production still at migration 0051 and missing cancel-order. No production writes, commit/push, or beta upload. Remaining gates: interactive payment methods/network interruption, hosted webhook and staged deployment acceptance.


## Admin/owner and remaining payment acceptance plan

1. Run real local customer/staff/owner authorization checks for products, settings, customer data, analytics, reviews and orders; verify payment/refund truth cannot be forged through direct admin REST updates.
2. Exercise fulfillment progression/history, backwards/terminal denial, verified cancellation/refund, and retry after an intentionally dropped checkout response.
3. Run Android owner/staff navigation, product editor, Orders/Fulfillment/Payments, More modules and settings in both themes, including actual UI mutations only against synthetic local fixtures.
4. Verify native PaymentSheet presentation/cancel and identify any 3DS/Google Pay requirements that need user interaction; report exact coverage without claiming unsupported wallet/browser challenges passed.
5. Fix reproduced blockers, run appropriate regressions and record evidence. Preserve existing changes; do not commit/deploy/upload.


### Admin acceptance progress — 2026-10-16

Steps 1–3 passed within the recorded scope: 8 real local role/authorization checks, 13 payment checks re-run after migration 0055, 2 real network-loss/delayed-webhook checks, isolated PostgreSQL boundaries/races, and native Android owner and staff workflows. Reproduced and corrected admin payment forgery (0055 + pending actions), IndexedStack Hero collisions, dashboard Material ink surfaces, remote thumbnail failures and animated theme button typography. Evidence and exact limits are in `docs/audit-fixes-verification-2026-10-15.md`.

Step 4 remains open for native card-form presentation/cancel, Google Pay/3DS and external redirect interaction; the SDK confirmation test does not substitute for it. No courier booking or production mutation. Final suite/static checks and local runtime cleanup follow. Add 0055 to the migration rollout before app release.
