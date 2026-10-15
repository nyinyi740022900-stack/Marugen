# Audit fixes verification — 2026-10-15

## Local outcome

ယခင် audit အချက် ၁–၇ နှင့် handoff payment blockers ၄ ခုကို source တွင် ပြင်ထားပြီး local tests ဖြင့် အတည်ပြုထားသည်။ Claude changes ကို ထိန်းထားသည်။ Commit/push/deploy/beta upload မလုပ်ထားပါ။

### Payment/stock blockers

1. PaymentIntent link ကို ဖြုတ်/ပြောင်းပြီး cancellation guard ကျော်ခြင်းကို database trigger ဖြင့် ပိတ်ထားသည်။
2. Failed link cleanup တွင် Stripe cancellation အတည်မပြုနိုင်ပါက stock မလွှတ်တော့ပါ။ Committed-link/lost-response နှင့် succeeded/processing refusal ကို test လုပ်ထားသည်။
3. Paid/refunded checkout keys ကို ဆက်ထိန်းပြီး retry တွင် မူလ order ပြန်ပေးသည်။ Client က PaymentSheet ထပ်မဖွင့်ပါ။ Cancelled attempt သာ verified cancellation ပြီးမှ key ပြန်သုံးနိုင်သည်။
4. Confirmation network errors ကို bounded retry လုပ်ပြီး မသေချာလျှင် မူလ order သို့သွားသည်။ Cart ကို authoritative paid confirmation ရမှ ရှင်းသည်။
5. Review မှထပ်တွေ့သည့် cancellation/item-insertion race ကို parent order row lock ဖြင့် ပိတ်ထားသည်။ Two-session tests တွင် cancellation အရင်/insert အရင် နှစ်မျိုးလုံး stock မှန်ကန်သည်။

### Existing completed work retained

Guest UI consistency၊ account-scoped addresses/stale forms၊ notification generation/rollback guards၊ review/stock boundaries၊ Order Detail authoritative refresh/session guards/cancellation dialog၊ Analytics large-text layout.

## Fresh checks

- Flutter suite: **190 passed**, no failures after the Android read-only guard regression. `/private/tmp/marugen-continued-final-flutter.log`.
- Flutter analysis: **No issues found** after the acceptance test additions. `/private/tmp/marugen-continued-final-analyze.log`.
- Deno helper suite: **16 passed**. `/private/tmp/payment-blockers-deno.log`.
- Payment Edge Function type checking: create-payment-intent, stripe-webhook, cancel-order, reconcile-pending-orders passed. `/private/tmp/payment-blockers-typecheck.log`.
- Isolated PostgreSQL: **23 stock/review assertions**, cancellation/link, idempotency/historical duplicate preservation, and genuine two-session reservation/cancellation checks passed. `/private/tmp/payment-blockers-sql-final.log`.

ဒီရလဒ်များသည် local/mocked verification ဖြစ်သည်။ Real charge/refund/shipment သို့မဟုတ် deployed Supabase/Stripe integration ကို စမ်းပြီးဟု မဆိုလိုပါ။

## Review

Scoped account/UI/SQL/payment reviews နှင့် independent broad final review: **approved; no additional material findings**. Read-only review ဖြစ်ပြီး live Stripe/deployed Edge/device acceptance ကို အစားမထိုးပါ။

## Remaining release gates

- Android guest acceptance: **passed** on Pixel_7 emulator, Android API 37.1 / 16 KB image. Restored the missing official image and built the native debug test APK. Shop screenshot shows two product columns. Profile/Orders guest login text position and width match; Profile-only appearance control, Light/Dark propagation, reachable Google login button, and privacy contact passed. Screenshot evidence: `output/releases/android-{shop,orders-guest,profile-light,profile-dark,login,privacy-policy}.png`; log `/private/tmp/marugen-native-acceptance.log`. Google OAuth completion remains untested. Later sections record signed-in local/native SDK acceptance; interactive card entry, Google Pay and 3DS remain open.
- Native smoke uses a test-only HTTP wrapper that blocks all Supabase non-read requests, including app-visit insertion. Its unit regression passed and the device test verified the blocked-write count. Normal app behavior is unchanged.
- Deployed read-only preflight: dashboard migration history ends at **0051**; **0052–0054 are absent**. Duplicate non-cancelled checkout-key groups: **0**. Orders RLS: **enabled**. pg_cron: installed. Both `cancel-stale-pending-orders` (10 minutes) and `reconcile-pending-orders` (5 minutes) jobs are active; Last 24 hours: stale cleanup 144 succeeded cron runs and reconciliation 288 succeeded cron runs, with no failed status groups returned. Cron SQL success alone does not prove the downstream HTTP request/webhook succeeded.
- Stripe dashboard is confirmed in **Test mode / Sandbox**. No live transaction was performed. Existing CLI credential refresh completed after reloading a stalled verification page; the same Marugen account was verified using the default test API. Provider smoke passed: idempotent create retry returns the same intent; cancellation; SGD 1.00 test-card payment succeeded; full test refund succeeded. Both parent PaymentIntents explicitly returned `livemode=false`; Refund omits that field, so mode was verified through its parent. Evidence: `output/releases/stripe-sandbox-provider-smoke.json` and `stripe-sandbox-provider-results.jpg`. These provider-only calls used no app order/customer and do not prove native checkout, database transitions, deployed webhook processing or stock behavior.
- Stripe sandbox: provider and real local stack lifecycle/replay/concurrency checks passed (details below). Hosted webhook configuration, interactive native PaymentSheet/card entry, Google Pay, 3DS and network-interruption acceptance remain open.
- Deployed readiness: migration history, orders RLS, duplicate-key preflight, function inventory and cron schedule/run status were checked read-only. Updated migrations/functions remain undeployed; required production secret values were not inspected.
- Deployed function inventory: **cancel-order is absent**. create-payment-intent was last updated 5 days ago; stripe-webhook/reconcile-pending-orders 14 days ago. The source fixes are not in these deployed versions.
- Backend contract rollout: historical duplicate preflight → migrations 0052/0053/0054/0055 → changed/new payment functions → app build. New app calls cancel-order; backend setup မပြီးမီ မဖြန့်ချိပါ။

Commit/release-ready ဟု အလိုအလျောက်မသတ်မှတ်ထားပါ။ Local fixes complete ဖြစ်ခြင်းနှင့် production acceptance ကို သီးခြား မှတ်တမ်းထားသည်။

## Continued native/payment acceptance

An additional Android release blocker was reproduced by an actual emulator test: Stripe initialization threw `PlatformException(flutter_stripe initialization failed)` because `MainActivity` extended `FlutterActivity`. Changed only the superclass/import to `FlutterFragmentActivity`, as required by the installed Stripe plugin. The same native initialization test then passed. Logs: `/private/tmp/marugen-stripe-native-red.log` (before), `/private/tmp/marugen-stripe-native-theme-check.log` (after). No speculative native theme changes were made; initialization passed with the existing themes.

A dedicated, unlinked local Supabase workspace is being prepared at `/private/tmp/marugen-local-acceptance` inside the `marugen-acceptance` Colima profile. Source migrations/functions are copied there; production is not linked or mutated. New opt-in local HTTP and native checkout acceptance targets exist but must not be reported as passing before execution. Stripe sandbox has no configured hosted webhook endpoints; the test listener forwards selected events only to loopback. Server secrets stay in private temporary files and are not in app defines or repository files.

### Local stack execution

All source migrations through 0054 applied successfully to the disposable local Supabase database. The initial Edge worker boot failed because Colima could not see the `/private/tmp` function bind mount; confirmed the missing entrypoint inside the container, then moved only public source/config to gitignored `output/local-acceptance`. Credentials remain in private temp files.

`supabase/tests/local_payment_acceptance.py`: **13 acceptance checks passed** against real local Auth/PostgREST/Edge/PostgreSQL and Stripe test mode, including unauthorized/direct insertion rejection, authoritative price/link/stock, pending/paid idempotency, cross-account and paid cancellation protection, exact-once stock restoration, decline/retry, signed webhook replay/reordering, staff-only/duplicate refund protection, and two buyers racing for one live fish. Evidence: `output/releases/local-payment-stack-acceptance.json`; log `/private/tmp/marugen-local-payment-acceptance.log`. Four real CLI-forwarded events also returned HTTP 200; the replay tests explicitly generate locally signed event envelopes and do not prove hosted webhook configuration.

After the Android Activity correction, the guest Android integration target passed again (both themes, matching guest login placement, login/privacy navigation). `/private/tmp/marugen-android-after-stripe-fix.log`. Analyzer clean: `/private/tmp/marugen-native-sdk-acceptance-analyze.log`. Native SDK/local backend confirmation subsequently passed (see next section). No production deployment or app release.

### Native SDK + real local backend — passed

`integration_test/android_local_checkout_test.dart` passed on the Android emulator. It signs in a synthetic local account, verifies the real checkout pay button is reachable with the correct SGD total, calls the production PaymentRepository against local create-payment-intent, initializes the native PaymentSheet, confirms through the actual native Stripe SDK using `pm_card_visa`, and waits for **real Stripe CLI-forwarded webhook delivery** to mark the order paid. No local replay is used by this native test. Order Detail renders paid, exactly one matching paid order is returned, and stock decreases by exactly one. The listener's HTTP-200 count increased from 4 to 5 during this run.

Evidence: `/private/tmp/marugen-native-local-checkout.log`; `output/releases/android-local-paid-order.png`. This SDK integration test does **not** tap through native card entry/PaymentSheet presentation, Google Pay, 3DS or an external browser redirect, and does not prove hosted production webhook configuration. The test app is removed by Flutter drive cleanup, so package intent queries run afterward cannot establish installed-app redirect availability; no manifest changes were made based on those queries.

### Final verification and cleanup

After all continued acceptance changes: full Flutter suite **190 passed**, analyzer **No issues found**, and `git diff --check` clean. Latest logs: `/private/tmp/marugen-continued-final-flutter.log`, `/private/tmp/marugen-continued-final-analyze.log`. Stopped the local function server and Stripe listener, backed up/stopped the local Supabase services, then stopped the dedicated Colima VM. Local test data remain in its Docker volume for repeat testing; production was unchanged. No commits, pushes or uploads were made.


## Admin/owner and network acceptance — continued

Actual local REST tests reproduced an authenticated staff/owner bypass: a pending order could be labelled paid without Stripe verification. Migration `0055_server_owned_order_financials.sql` now reserves paid/refunded transitions and checkout amount/identity/promo/refund fields for trusted backend database roles. The admin pending-order action no longer offers Paid. Normal staff/owner fulfillment remains permitted. Migration 0055 is applied only to the disposable local database; it must join the backend rollout before release.

- `supabase/tests/local_admin_acceptance.py`: **8 checks passed** against real local Auth/REST/DB. Both staff and owner are denied forged payment/refund data; customer self-promotion, product writes, settings writes, other customer profiles and raw analytics are restricted. Staff/owner product stock, shared admin settings and forward fulfillment/history work. Evidence: `output/releases/local-admin-acceptance.json`, `/private/tmp/marugen-admin-green.log`.
- All **13 local payment checks passed again after 0055**, proving that verified backend payments/refunds still work: `/private/tmp/marugen-payment-after-admin-guard.log`.
- `supabase/tests/local_network_acceptance.py`: **2 checks passed**. A proxy drops a response after checkout commits; retry returns the same order/payment and reserves stock once. With webhook forwarding deliberately stopped, a successful Stripe test payment is recovered by the retry endpoint without another charge; it is subsequently refunded in test mode. Evidence: `output/releases/local-network-acceptance.json`, `/private/tmp/marugen-network-acceptance.log`. This tests real HTTP loss/server recovery, not full offline UI.
- Isolated PostgreSQL suite passed with the new financial-authority regression and both concurrent reservation/cancellation orderings: `/private/tmp/marugen-admin-sql.log`. The bootstrap now includes actual promo/refund migrations required by the new trigger.

Native Android owner testing also reproduced duplicate default FAB Hero tags when opening the product editor and dashboard ListTile ink-background assertions. Only the active IndexedStack tab now participates in Hero animations/tickers; populated dashboard cards provide their own Material ink surface. Dashboard copy accurately states that stock remains reserved until cancellation is confirmed. Native final results and fresh full-suite verification are recorded below when complete.


### Android owner — passed

`integration_test/android_local_admin_test.dart` completed on the Pixel_7 emulator with a real synthetic local owner account. It creates and verifies a product via the actual editor, navigates Home/Products/Orders (All/Fulfillment/Payments)/Knowledge/Promo Codes/Reviews/Analytics/Settings, verifies the navigation bar stays fixed, changes Light→Dark→Light, logs out, and verifies `/admin` is denied afterward. Log: `/private/tmp/marugen-android-owner-final.log`; screenshots: `output/releases/android-owner-*.png`. Dashboard, payments and dark settings screenshots were visually inspected.

The run additionally reproduced remote Knowledge thumbnails failing with HTTP 429 and an animated light/dark OutlinedButton TextStyle inheritance assertion. Knowledge thumbnails now use a visible fallback; product/article/service editors also handle remote image failures. The dark outlined-button theme now declares matching label typography. Two dedicated widget regressions pass, including the exact theme interpolation red→green: `/private/tmp/marugen-theme-transition-red.log`, `/private/tmp/marugen-admin-ui-regressions.log`. These are real fixes rather than suppressing framework exceptions in the acceptance target.


### Android staff — passed (2026-10-16)

The same native acceptance target also passed as staff, including real product creation, all listed admin destinations, fixed navigation geometry, both theme transitions, logout and denied admin re-entry. Log: `/private/tmp/marugen-android-staff.log`. Screenshot `output/releases/android-staff-orders-dark.png` was visually inspected. Staff/owner accounts used here are synthetic local fixtures; no production staff account was created. Existing staff and owner roles share admin privileges; owner-only refund/settings permissions have not been introduced.

Coverage remains bounded: the native run does not perform courier booking, print through a physical printer, edit every Knowledge/Promo/Review form, authenticate with a real Google account, or tap the native Stripe card form/cancel/3DS/Google Pay. Those device/service acceptance steps remain open. Native SDK confirmation, backend refund/network/idempotency and authorization coverage above must not be described as proof of these separate interactions. Production remains undeployed; no commit/push/upload.


### Final admin verification — 2026-10-16

Full Flutter suite: **193 passed**, no failures (`/private/tmp/marugen-admin-final-flutter.log`). Static analysis: **No issues found** (`/private/tmp/marugen-admin-final-analyze.log`). Formatting of the 11 touched admin/theme/integration/regression files reported 0 changes; `git diff --check` is clean. Both native role runs passed; the financial/network/SQL checks above remain successful. The function server was stopped and Supabase local services were backed up/stopped. No commit, push, production migration/function deploy or closed-beta upload was performed.
