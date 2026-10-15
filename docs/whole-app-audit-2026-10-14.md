# E-Commerce Audit — Marugen

## Store classification

Single-store B2C shop ဖြစ်သည်။ Koi/Arowana သည် unique live inventory၊ food/accessories သည် quantity/variant/size stock ဖြစ်သည်။ Flutter/Riverpod/GoRouter၊ Supabase/PostgreSQL၊ Stripe နှင့် shop delivery/EasyParcel ကို သုံးထားသည်။ Marketplace feature ထပ်တိုးရန် မလိုပါ။

## Executive verdict

**အရေးကြီး payment defect ၁ ခု၊ account-isolation defect ၂ ခု၊ Order Detail/Analytics defect ၂ ခုကို isolated tests ဖြင့် ပြန်ဖြစ်အောင် အတည်ပြုထားသည်။** Database source permissions တွင် ထပ်စစ်/ပြင်ရမည့် အန္တရာယ် ၂ ခု ရှိသည်။ Tests အောင်မြင်ခြင်းတစ်ခုတည်းဖြင့် release-ready ဟု မသတ်မှတ်နိုင်သေးပါ။

App တစ်ခုလုံး၏ feature inventory/pattern scan လုပ်ထားသော်လည်း page အားလုံးကို native device ပေါ်တွင် စမ်းပြီးဟု မဆိုလိုပါ။ Production charge/refund/shipment/delete/data mutation မလုပ်ထားပါ။ ယခင် guest UI fixes ကို ထိန်းသိမ်းထားသည်။ ဒီအဆင့်မှာ audit/plan သာဖြစ်ပြီး အောက်ပါအမှားအသစ်များကို မပြင်ရသေးပါ။

## Checked scope and verification

- Feature source files **76**၊ screen/shell/form surface files **39**: inventory နှင့် source-pattern scan။ File-level evidence: `output/audit/surface-inventory.json`.
- Edge Function entry points **16**၊ migrations **51**၊ Flutter test files **23**: inventory။ Payment/webhook/refund/reconciliation, auth/session providers, deletion, stock/review RLS boundaries ကို ဦးစားပေး source trace လုပ်ထားသည်။ အားလုံး exhaustive line-by-line/runtime စစ်ပြီးဟု မဆိုလိုပါ။
- Flutter baseline: **140 tests passed**. Log `/private/tmp/whole-app-flutter-tests.log`.
- Deno backend helper baseline: **7 tests passed**, type checking enabled. Remarks/deletion helpers only; deployed payment integration မဟုတ်ပါ။ Log `/private/tmp/whole-app-deno-tests.log`.
- Dart audit diagnostics **4 reproductions passed**: address cache, late notification, stale order snapshot, Analytics overflow။ Passing ဆိုသည်မှာ defect ပြန်ဖြစ်သည်ကို test က သိရှိခြင်းဖြစ်သည်။ Source `output/audit/whole_app_diagnostics_test.dart.txt`; executable copy `/private/tmp/marugen_whole_app_diagnostics_test.dart`; log `output/audit/whole-app-diagnostics.log`.
- Stripe webhook အစစ်၏ handler ကို mock Stripe/DB ports နှင့် run လုပ်ထားသည်။ Failed→success နှင့် success→late-failed event sequences နှစ်မျိုးလုံး defect ပြန်ဖြစ်သည်။ `output/audit/stripe_webhook_diagnostic.ts` / `stripe-webhook-diagnostic.log`.
- Analyzer run တွင် audit diagnostic ကို output/ အောက်မှ test source အဖြစ်မသတ်မှတ်နိုင်လို့ `setMockInitialValues` warning ၁ ခုထွက်ခဲ့သည်။ ထို audit-only source ကို `.dart.txt` အဖြစ်ပြောင်းပြီး executable copy ကို temporary directory သို့ရွှေ့ထားသည်။ Final analyzer rerun: **No issues found** (`/private/tmp/whole-app-analyze-final.log`). Automatic approval review usage-limit failure ကြောင့် ပထမ rerun မလုပ်နိုင်ခဲ့သော်လည်း user continue ပြီးနောက် ပုံမှန် approval လမ်းကြောင်းမှ ပြန် run နိုင်ခဲ့သည်။
- Android emulator သည် configured Android 37.1 system image မရှိသဖြင့် မဖွင့်နိုင်သေးပါ။ Physical Android, Google credential login, TalkBack, native Stripe sandbox, EasyParcel booking, iPhone/iPad runtime နှင့် performance profiling မစမ်းထားပါ။

## Buy-path scorecard

| Step | Status | Evidence / gap |
| --- | --- | --- |
| Discovery/Card/PDP | PARTIAL | Existing responsive/options/accessibility regressions pass; real inventory/device walkthrough pending |
| Cart | PARTIAL | Refresh/account-race/undo tests pass; native interrupted-payment/process-restart checks pending |
| Checkout/Payment | FAIL | Finding 1: paid payment can leave order cancelled |
| Account/address | FAIL | Findings 2–3: stale address/notification data crosses account changes |
| Stock | SOURCE RISK | Finding 4: direct client inserts reach privileged stock trigger |
| Orders/Fulfillment | PARTIAL | Finding 6: stale detail snapshot; shipment/refund runtime pending |
| Reviews | SOURCE RISK | Purchase/unique gate exists; finding 5: admin-only columns insufficiently protected |
| Contact/Help/Knowledge | PARTIAL | Surface scan complete; device links and shop-owner content acceptance pending |

## P0 — Must fix before widening release

### 1. Failed payment/reordered events can cancel a paid order

**Location:** `supabase/functions/stripe-webhook/index.ts:68,82–93`; related checkout cancellation and stock/status triggers.

Original handler test: failed event changes pending→cancelled; later succeeded event returns HTTP 200 but order stays cancelled. Conversely, succeeded changes pending→paid and late failed event changes paid→cancelled. The success branch only matches pending; failure branch also matches paid. Cancellation releases stock; reconciliation scans pending only.

Payment attempt failure can be retried on the same PaymentIntent; it is not terminal cancellation. See [Stripe PaymentIntent lifecycle](https://docs.stripe.com/payments/paymentintents/lifecycle). This defect can leave payment received but order/stock in the wrong state. Tests use mock ports; no real charge occurred.

**Fix/acceptance:** Separate retryable failure from terminal cancellation; verify current Stripe state before releasing stock, match order/PaymentIntent/amount/currency, protect paid states from stale events, and handle zero-row updates explicitly. Make cancellation server-owned and retry-safe. Test decline→retry success, reordered/duplicate events, late success vs cancellation, native sheet dismissal, dropped responses and stock recovery. Do not blindly resurrect an order after released stock has been sold elsewhere.

## P1 — Account isolation and permissions

### 2. Addresses remain cached after account changes

**Location:** `lib/features/profile/presentation/address_providers.dart:8`.

Load A addresses, switch active account to B: actual provider returns A addresses and repository load count remains 1. Provider watches repository but not account identity. Checkout may show/use an old shipping address.

**Fix/acceptance:** Watch active user identity, clear on logout, gate account-only address UI, and validate selected address owner against checkout owner. Test A→guest→B, guest→login, delayed old response and session expiry.

### 3. Late notification response overwrites the new account inbox

**Location:** `lib/features/notifications/presentation/notification_providers.dart:78–83`.

Start A load, switch to B, complete B response then A response: notifier ends with A notification. Loads/optimistic rollback do not guard generation/owner.

**Fix/acceptance:** Guard load, read/read-all rollback and subscriptions by account/generation. Test A→B, logout, concurrent read failures and realtime inserts. Reuse guarded Cart/Wishlist patterns.

### 4. Customer inserts bypass server stock validation

**Location:** `supabase/migrations/0026_lock_down_order_inserts.sql:20–38`; `0020_variant_size_stocks.sql:33–99`; `0001_init.sql:159–166`.

Source policies still allow customer-owned pending orders and order-items to be inserted directly. SECURITY DEFINER stock trigger subtracts `new.quantity`; the checked schema has no positive-quantity constraint. Direct negative commodity/variant quantities can increase stock; positive inserts can reserve stock without the server payment flow.

**Limit:** Repository schema finding; deployed policies/constraints and actual SQL behavior have not been verified. No stock write/exploit performed.

**Fix/acceptance:** Remove client insert policies when creation is service-only; add positive quantity/variant ownership/live-fish constraints and trigger guards. Use an isolated migrated DB to prove invalid/direct customer inserts fail and legitimate reservations remain atomic.

### 5. Review authors can write shop reply/moderation columns

**Location:** `0005_reviews.sql` author update policy; `0011_review_moderation.sql`; `0031_review_shop_reply.sql:12`; `0037_lock_review_reassignment.sql:14–17`.

Author update permission checks row ownership; existing trigger protects only product_id/user_id. Source does not protect admin_reply/admin_reply_at/is_hidden from author changes. A buyer can forge a shop reply or undo moderation through a direct update.

**Limit:** Source permission gap; deployed column grants/constraints and isolated SQL tests remain required.

**Fix/acceptance:** Protect admin fields on INSERT and UPDATE with explicit permissions or role-aware triggers. Reject customer forged replies/unhide/reassignment; preserve admin moderation and verified-buyer rating/comment edits. [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) documents why service-role bypass and client/privileged boundaries need separate checks.

## P2 — Operational UI

### 6. Order Detail keeps a stale navigation snapshot

**Location:** `lib/features/orders/presentation/order_detail_screen.dart:54–58`.

Pass pending order as navigation extra while authoritative provider returns delivered: screen does not fetch provider (count 0) and still shows Cancel Order. Most list navigation passes the extra snapshot.

**Fix/acceptance:** Treat extra as initial content, then subscribe/refetch detail and support refresh. Scope detail to active owner/role. Test pending→paid/packing/shipped/delivered, failure recovery and expired session; retain backend cancellation guards.

### 7. Admin Analytics overflows at large text

**Location:** `lib/features/admin/analytics/admin_analytics_screen.dart:302–340`.

Actual screen at 320×640 and 2× text with one visit fixture reports bottom overflows of 23/48/106 pixels. Fixed 110-pixel chart/narrow labels cannot accommodate wrapping/scaling.

**Fix/acceptance:** Adapt chart height/density/labels without disabling text scaling. Test Light/Dark, all periods, long counts, phone/landscape/tablet.

## P2 — Defer / do not build yet

Keep single-store scope. Avoid new marketplace/social/AI modules until payment/account/permissions gates pass. Raw exception copy is a follow-up pattern in seven admin surfaces: Analytics, Dashboard, Payments, Product Edit, Service Edit, Article Form and Variety Form. Standardize actionable retry/save recovery and log technical errors; these are scan candidates, not seven reproduced runtime defects.

## Recommended sequence and acceptance work

1. Payment lifecycle/cancellation/reconciliation/stock boundary: fix 1, add isolated handler regressions, then Stripe sandbox/device checks.
2. Account isolation: fix 2–3, then inspect other asynchronous account data (including own review) for the same stale-completion pattern.
3. Database boundaries: run `output/audit/database-readonly-checks.sql` against authorized deployed DB; fix/test 4–5 on an isolated DB before deployment. The script reads schema/secret names, never keys/customer data.
4. Order/UI state: fix 6–7 and identified recovery candidates, rerun targeted tests.
5. Android acceptance: install/restore the configured image or connect a physical Android; real app login, back, keyboard, appearance, large text, TalkBack, offline/reconnect and payment checks.
6. Cross-platform/release: targeted iPhone/iPad checks, sandbox concurrency/refund/shipping/deletion evidence, full tests/analyzer/review, then separately authorized build/upload.

## Explicit non-goals / limits

No version bump, commit/push, migration/function deployment or Closed beta upload during this audit. No invented 40/40 or native score. First-pass coverage means inventory/source scan across all feature surfaces plus deep verification of prioritized boundaries; it does not prove all 76 files or every route/device flow correct.
