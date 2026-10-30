# Whole-app audit — Android + iOS (2026-10-30)

Dev tester အမြင်ဖြင့် app တစ်ခုလုံး (customer app၊ owner/staff admin၊ Supabase backend) ကို `main` @ `5db01fb` / 1.0.24 (29) အပေါ်မှာ စစ်ထားသည်။ Code မပြင်ရသေးပါ။ Production data ကို မပြောင်းထားပါ။ (Debug build ကလည်း analytics ကို prod ထဲ ရေးသောကြောင့် — D2 — live run မလုပ်ခဲ့ပါ။)

## Fix status — P0 (2026-10-30, local only)

P0-1 နဲ့ P0-2 ကို source မှာ ပြင်ပြီး local tests နဲ့ အတည်ပြုထားသည်။ **Commit / production deploy / app release မလုပ်ရသေးပါ။**

- **P0-1 promo:** Migration [0071_private_promo_codes.sql](../supabase/migrations/0071_private_promo_codes.sql) က public select policy ကို ဖြုတ်ပြီး exact-match (case-insensitive) function ၂ ခု ထည့်သည် — `check_promo_code` (signed-in customer၊ active code + "already used") နဲ့ `find_promo_code` (service role only)။ App ([promo_repository.dart](../lib/features/promo/data/promo_repository.dart)) နဲ့ `create-payment-intent` / `_shared/shipping_api.ts` က `ilike` အစား ဒီ function တွေကို သုံးသည်။ Checkout မှာ သုံးပြီးသား code ကို apply ချိန်မှာပဲ "You have already used this promo code." ပြသည်။
- **P0-2 time:** Model အားလုံး [server_time.dart](../lib/shared/utils/server_time.dart) နဲ့ local time ပြောင်းပြီး parse လုပ်သည် (order၊ invoice၊ notification၊ review၊ wishlist၊ promo၊ profile၊ article၊ cancellation၊ EasyParcel၊ analytics)။ Offset မပါဘဲ server ကို ပို့နေခဲ့သော `published_at`၊ `admin_reply_at`၊ analytics `since` တို့ကို UTC နဲ့ ပို့သည်။ Promo "Expiry date" ကို ရွေးတဲ့နေ့ **23:59:59 (device local)** အထိ သုံးလို့ရအောင် UTC နဲ့ သိမ်းသည် — အရင်က ၎င်းနေ့ **08:00 SGT** မှာ သက်တမ်းကုန်ခဲ့သည် (ရှိပြီးသား code တွေက ပြန် save မှ ပြောင်းမည်)။

### Verification

- SQL: `supabase/tests/run_private_promo_codes.sh` pass (anon/customer table listing 0 rows၊ `%` `_` `*` empty → no match၊ exact case-insensitive match၊ already-used flag၊ anon denied၊ server-only function denied to customers၊ admin CRUD မပျက်)။ `--baseline` (0071 မပါ) က "Anonymous caller can list promo codes" နဲ့ fail — leak ကို reproduce လုပ်နိုင်။ `run_promo_release.sh` pass။
- Deno: `deno test --allow-env supabase/functions` **104 passed**၊ new RPC test သည် မူလ `shipping_api.ts` ပေါ်မှာ fail ပြီး fix ပေါ်မှာ pass။ `create-payment-intent`၊ `checkout-shipping-quote` type-check pass။
- Flutter: `test/promo_repository_test.dart` (RPC request/body၊ wildcard literal၊ blank input)၊ checkout "already used" widget test၊ `test/server_time_test.dart` (local wall-clock၊ SGT 07:30 order = Oct 30၊ promo expiry round trip)။ Timezone tests သည် မူလ models ပေါ်မှာ fail ပြီး fix ပေါ်မှာ pass။

### Rollout (owner လုပ်ရမည်၊ အစဉ်လိုက်)

1. Production DB မှာ `0071_private_promo_codes.sql` apply (SQL editor သို့ authorized migration process)။
2. `create-payment-intent` နဲ့ `checkout-shipping-quote` ကို redeploy (function ၂ ခုလုံး `find_promo_code` ကို သုံးလို့ step 1 ပြီးမှ)။
3. App build အသစ် ထုတ်။ Step 1 နဲ့ ဒီ build ကြားမှာ **1.0.24 beta app ထဲက promo apply က "Invalid promo code" ပြမည်** (leak ပိတ်ခြင်းရဲ့ ဈေး)။ Checkout ကိုယ်တိုင် မပျက်ပါ။
4. Admin က အသုံးမပြုချင်တော့တဲ့ / ပေါက်ကြားပြီးဖြစ်နိုင်တဲ့ private code တွေကို deactivate/rotate လုပ်ရန် စဉ်းစား (ဒီ fix မတိုင်ခင် ဘယ်သူ list ဆွဲခဲ့သလဲ မသိနိုင်)။

Old builds က `published_at` / `admin_reply_at` ကို ၈ နာရီ ကျော်ပြီး သိမ်းခဲ့သည် (app မှာ မပြလို့ မမြင်ရ)။ Data ပြင်ဆင်ခြင်း မလုပ်ထားပါ။

## Store classification

Single-store B2C (Singapore)။ Koi/Arowana = unique live inventory (qty 1)၊ fish food/accessories = variant × size stock။ Stripe (server-calculated total, webhook → paid)၊ courier (EasyParcel/TracX) + live fish ကို ဆိုင်က ကိုယ်တိုင်ပို့။ Self-collect မရှိ။ Android closed beta သာ ထုတ်ရသေးပြီး iOS store release မလုပ်ရသေးပါ။

## Executive verdict

Buy path အလုပ်လုပ်ပြီး payment/stock integrity (server pricing, idempotency, webhook signature, verified refunds, role-escalation guard, account deletion) ခိုင်မာပါတယ်။ ဒါပေမဲ့ **(1) active promo code အားလုံးကို app ထဲပါတဲ့ public key နဲ့ ဘယ်သူမဆို ဆွဲထုတ်ပြီး သုံးလို့ရနေခြင်း** နဲ့ **(2) order / invoice / notification အချိန်အားလုံးကို UTC နဲ့ပြလို့ စင်ကာပူအချိန်ထက် ၈ နာရီ နောက်ကျပြီး မနက် 00:00–07:59 order တွေ ရက်စွဲပါ မှားခြင်း** — ဒီ ၂ ခုကို အရင်ပြင်ရပါမယ်။ iOS ကတော့ paid Apple Developer account မရှိသေးလို့ push / Apple sign-in / Apple Pay မပြည့်စုံသေးပြီး App Review risk အချို့ ကျန်ပါတယ်။

## Checked scope and evidence

- `flutter analyze`: **No issues found**.
- `flutter test`: **496 passed / 4 failed**။ Fail ၄ ခုလုံး print tests ဖြစ်ပြီး `pdftoppm` (poppler) မရှိခြင်းနဲ့ gitignored `output/split-parcels/QSP223261096.pdf` ကို မှီခိုခြင်းကြောင့်ပါ (code regression မဟုတ်)။
- Timezone bug ကို script နဲ့ reproduce လုပ်ထားသည်: Supabase `2026-10-29T23:30:00+00:00` (= 30 Oct 07:30 SGT) → app ပြပုံ `Oct 29, 2026 11:30 PM`။
- Source-level စစ်ထားသည်: release merged manifest (minSdk 24 / targetSdk 36၊ `POST_NOTIFICATIONS` merged၊ `<queries>`)၊ latest AAB contents (`.env` asset ပါ)၊ iOS Info.plist / entitlements / xcodeproj၊ migrations RLS၊ payment / push / delivery functions။
- `output/ui-final-native/ios-confirmed/*.png` ၈ ပုံလုံး MD5 တူ (blank) — 23 Oct iOS visual evidence မမှန်ပါ။
- **မလုပ်ရသေး**: physical device run၊ live payment/refund၊ courier booking၊ real Google/Apple sign-in၊ TalkBack/VoiceOver။

## Buy-path scorecard

| Step | Status | Evidence / gap |
| --- | --- | --- |
| Card CTAs | PASS* | Quick-add / Buy / Chat ရှိ။ Live-fish ခလုတ်က cart icon ဖြစ်ပေမဲ့ Buy Now လုပ် (U5) |
| PDP CTAs | PASS* | Sticky Add / Buy / Chat ✓။ Image indicator မရှိ (U4)၊ cache stale (P1-6) |
| Cart | PARTIAL | Per-account persist ✓။ Guest→login merge မရှိ (U3)၊ offline hydrate data loss (U7) |
| Checkout/Payment | PARTIAL | Server-authoritative ✓။ Promo exposure (P0-1)၊ address validation နောက်ကျ (P1-2)၊ mismatch reservation (P1-8) |
| Orders | PARTIAL | Timeline / cancel / refund ✓။ UTC time (P0-2)၊ Pay-now မရှိ (P1-8)၊ push tap (P1-1) |
| Reviews | PARTIAL | Verified purchase ✓။ Delivered မဖြစ်ခင် ရေးလို့ရ (U1) |
| Chat | PARTIAL | WhatsApp ✓။ Phone fallback ဘယ်တော့မှ မရောက် (A3) |

## P0 — Release မချဲ့ခင် ပြင်ရမည်

### P0-1 Active promo code အားလုံး public ဖြစ်နေ + wildcard နဲ့ apply လို့ရ

- **Where:** [0006_promo_codes.sql:16](../supabase/migrations/0006_promo_codes.sql) — `for select using (active = true)` (anon အပါအဝင် ဘယ် role မဆို)။ [promo_repository.dart:14](../lib/features/promo/data/promo_repository.dart) နဲ့ [create-payment-intent/index.ts:495](../supabase/functions/create-payment-intent/index.ts) — `ilike` သုံး။
- **Impact:** App ထဲပါတဲ့ anon key နဲ့ `GET /rest/v1/promo_codes?select=*` ခေါ်ရုံနဲ့ active code (VIP/influencer code အပါအဝင်) အားလုံး ရနိုင်။ `ilike` မှာ `%` / `_` က wildcard ဖြစ်လို့ active code တစ်ခုတည်းရှိရင် `%` ရိုက်ရုံနဲ့ client မှာ "applied" ပြပြီး server ကလည်း discount ပေးမယ်။
- **Fix:** Public select policy ဖြုတ်။ Exact match (`lower(code) = lower(input)`) သုံးတဲ့ `security definer` RPC (`check_promo_code`) ကနေ valid/discount ပဲ ပြန်ပေး။ Server ဘက်လည်း `ilike` → exact match ပြောင်း (သို့) wildcard escape။ Per-user "already used" ကို apply ချိန်မှာ စစ်ပေး။

### P0-2 အချိန်/ရက်စွဲ အားလုံး UTC နဲ့ပြ (SGT ထက် ၈ နာရီ နောက်ကျ)

- **Where:** Models က `DateTime.parse` ကို UTC အတိုင်းထား — [order.dart:384](../lib/shared/models/order.dart)၊ `app_notification.dart:50`၊ `review.dart:45`၊ `wishlist_item.dart:25`၊ `promo_code.dart:60`၊ `app_user.dart:50`။ Display: [orders_screen.dart:118](../lib/features/orders/presentation/orders_screen.dart)၊ [order_detail_screen.dart:282](../lib/features/orders/presentation/order_detail_screen.dart)၊ **[invoice_pdf.dart:127](../lib/features/orders/utils/invoice_pdf.dart)**၊ `notifications_screen.dart:421`၊ `reviews_section.dart:477`၊ `admin_orders_screen.dart:472`၊ `admin_payments_screen.dart:181`။ `trackingUpdatedAt` တစ်ခုပဲ `.toLocal()` သုံးထား။
- **Impact:** 30 Oct 07:30 SGT order ကို "Oct 29, 11:30 PM" လို့ပြ။ Tax invoice ရက်စွဲပါ မှား။ Customer/owner နှစ်ဘက်လုံး ရှုပ်ထွေး။
- **Fix:** Model parse ချိန်မှာ `.toLocal()` (တစ်နေရာတည်း)။ `TZ=Asia/Singapore` နဲ့ regression test ထည့်။

## P1 — မကြာခင် ပြင်သင့် (bug / conversion / operations)

| ID | Finding | Where | Fix |
| --- | --- | --- | --- |
| P1-1 | Push notification ကို နှိပ်ရင် order ဆီ မရောက်ဘဲ home ပဲ ပွင့် (Android + iOS)။ Foreground SnackBar မှာလည်း action မပါ | [push_notification_service.dart](../lib/core/notifications/push_notification_service.dart) — `onMessageOpenedApp` / `getInitialMessage` မရှိ | Push data မှာ `order_id` ပါပြီးသား → `/orders/<id>` ကို navigate |
| P1-2 | Address form က "Required" ပဲစစ်၊ server က SG phone `^[3689]\d{7}$` + postal ၆ လုံး တောင်း → checkout ရောက်မှ error | [address_book_screen.dart:391-432](../lib/features/profile/presentation/address_book_screen.dart) vs [delivery.ts:132-141](../supabase/functions/_shared/delivery.ts) | Client မှာ rule တူတူ validate၊ postal `maxLength: 6` digits-only၊ City ကို "Singapore" prefill၊ `autofillHints` |
| P1-3 | Image upload မှာ `maxWidth` မရှိ၊ grid မှာ `memCacheWidth` မရှိ → full-res (≈4000px) ပုံတွေ download/decode → shop scroll လေး၊ data များ၊ low-end Android OOM risk | `admin_product_edit_screen.dart:283`၊ `profile_screen.dart:44` စသည်၊ `product_card.dart` | Pick မှာ `maxWidth: 1600`၊ thumbnail မှာ `memCacheWidth` (သို့) Supabase image transform |
| P1-4 | Admin price validation မရှိ: variant price မှား/ကွက်လပ် → **S$0.00** နဲ့ save၊ main price မှားရင် null → "Contact for price" ဖြစ်သွား၊ အနုတ်ဈေး/stock လက်ခံ၊ DB check constraint မရှိ | [admin_product_edit_screen.dart:246](../lib/features/admin/products/admin_product_edit_screen.dart)၊ `:687`၊ `:1069` | Validator (>0, decimal)၊ sale < price စစ်၊ DB `check (price > 0)` / `stock_quantity >= 0` |
| P1-5 | Dashboard "Total Revenue / This Week" မှား: Orders tab ရဲ့ status filter ကို လိုက်ပြောင်း၊ pending (မပေးရသေး) order ပါ ထည့်တွက်၊ partial refund မနုတ်၊ PostgREST 1000 rows မှာ ဖြတ်သွား | [admin_dashboard_screen.dart:250-270](../lib/features/admin/dashboard/admin_dashboard_screen.dart)၊ [orders_providers.dart:125](../lib/features/orders/presentation/orders_providers.dart) | Server-side aggregate RPC (paid…delivered, minus refunds) သီးသန့် |
| P1-6 | Shop/PDP data stale: Shop မှာ pull-to-refresh မရှိ၊ `productDetailProvider` ကို ဘယ်တော့မှ refresh မလုပ်၊ checkout ပြီးရင်လည်း product cache မ invalidate → ဝယ်ပြီးသား koi ကို "Available" ဆက်ပြ | `shop_screen.dart`၊ `shop_providers.dart`၊ `checkout_screen.dart` success path | Shop/PDP `RefreshIndicator`၊ PDP `autoDispose`၊ order ပြီးရင် product providers invalidate |
| P1-7 | FCM token: account တစ်ခု device တစ်ခုပဲ (`profiles.fcm_token`)၊ token register ချိန် တခြား profile က token တူကို မဖျက် → offline logout ဖြစ်ခဲ့ရင် A ရဲ့ order push တွေ B ဖုန်းထဲ ရောက် | `push_notification_service.dart`၊ [push.ts](../supabase/functions/_shared/push.ts) | `device_tokens` table (user × token, unique token)၊ register RPC က တခြား user ဆီက token တူ ဖျက် |
| P1-8 | Pending order မှာ "Pay now" မရှိ (Cancel/Reorder ပဲ)။ PaymentSheet ပိတ်တိုင်း cancelled order တစ်ခု My Orders ထဲ ပေါ်။ Client total mismatch (`StateError`) ဖြစ်ရင် pending order ကို မ cancel → live fish ~30 မိနစ် lock | [order_detail_screen.dart:616](../lib/features/orders/presentation/order_detail_screen.dart)၊ [checkout_screen.dart:394](../lib/features/orders/presentation/checkout_screen.dart)၊ `order_repository.dart:17` | Pending order မှာ "Complete payment"၊ never-paid cancelled တွေကို default ဖျောက်၊ mismatch path မှာ `cancelMyOrder` |
| P1-9 | Handled error တွေ Crashlytics မရောက်: `CrashReporting.recordError` ကို ဘယ်မှာမှ မခေါ်၊ checkout/booking failure တွေက `developer.log` (release မှာ မမြင်ရ) ပဲ | `crash_reporting.dart`၊ `error_message.dart` | `friendlyErrorMessage` + checkout catch မှာ non-fatal record |

## P2 — Platform / UX polish

### Android

- **A1 Back ခလုတ်**: Customer/Admin shell မှာ `PopScope` မရှိ → Orders/Profile tab ကနေ back နှိပ်ရင် Shop tab ကို မပြန်ဘဲ app ထွက်သွား။ ([customer_shell.dart](../lib/features/shop/presentation/customer_shell.dart)၊ `admin_shell.dart`)
- **A2 Notification small icon**: `default_notification_icon` meta-data / FCM `icon` မရှိ → launcher icon ကို သုံးလို့ status bar မှာ အဖြူတုံး/စက်ဝိုင်း ပေါ်။ Monochrome `ic_stat_notify` ထည့်။
- **A3 Contact fallback**: [contact_launcher.dart:14-23](../lib/shared/utils/contact_launcher.dart) က `canLaunchUrl(tel:)` သုံးပေမဲ့ manifest `<queries>` မှာ `tel` မရှိ (Android 11+ မှာ false)။ iOS မှာလည်း https (wa.me) က အမြဲအောင်လို့ phone ကို ဘယ်တော့မှ မရောက် → WhatsApp မရှိသူ wa.me web page ပဲ မြင်။ "Call" / "WhatsApp" ခလုတ် ခွဲပေး + `<queries>` / `LSApplicationQueriesSchemes`။

### iOS

- **I1 Paid Apple Developer Program** လိုအပ်: push (`aps-environment`)၊ Sign in with Apple၊ Apple Pay၊ TestFlight။ Apple Pay off ထားလို့ iOS conversion နိမ့်မယ် (known)။
- **I2 Sign-in buttons**: Apple ခလုတ်က generic `OutlinedButton` + `Icons.apple` (HIG မကိုက် — review risk)၊ Google က `Icons.g_mobiledata` (official "G" မဟုတ်)။ `SignInWithAppleButton` + official Google asset သုံး။ ([login_screen.dart:395-418](../lib/features/auth/presentation/login_screen.dart))
- **I3 Info.plist**: Camera ကို ဘယ်မှာမှ မသုံး (gallery ပဲ) ပေမဲ့ `NSCameraUsageDescription` ရှိ၊ "product reviews" photo feature မရှိ၊ photo library ထဲ save မလုပ်ပေမဲ့ `NSPhotoLibraryAddUsageDescription` ရှိ (5.1.1 review risk)။ `ITSAppUsesNonExemptEncryption=false` ထည့်။
- **I4 iOS visual evidence blank**: `ios-confirmed` ၈ ပုံ MD5 တူ → iOS screen တွေကို simulator/device ပေါ်မှာ ပြန်ရိုက်စစ်ရန်။
- **I5 Orientation**: iPhone/Android phone တွေ landscape လှည့်လို့ရ (lock မရှိ) → PDP မှာ header + tab + CTA bar ကြောင့် content မမြင်သလောက်။ Phone ကို portrait lock (tablet/iPad ချန်)။

### Common UX

- **U1** Review ကို `paid` ဖြစ်တာနဲ့ ရေးလို့ရ (delivered မဖြစ်ခင်)၊ refund ပြီးလည်း review ကျန် — [0009_verified_reviews.sql:28](../supabase/migrations/0009_verified_reviews.sql)၊ `review_repository.dart:87`။ `delivered` ပဲ ခွင့်ပြု။
- **U2** Profile မှာ Change password / Edit name မရှိ (forgot-password email နဲ့ပဲ ပြောင်းလို့ရ)။
- **U3** Guest cart ကို login (Profile ကနေ) ပြီးရင် account cart ထဲ merge မလုပ် → cart ဗလာ ဖြစ်သွားသလို ခံစားရ (checkout လမ်းကြောင်းမှာတော့ intent နဲ့ ထိန်းထား)။
- **U4** PDP image carousel မှာ page indicator (dots / 1/5) မရှိ ([product_detail_screen.dart:371](../lib/features/shop/presentation/product_detail_screen.dart))။
- **U5** Live fish card ခလုတ်က add-to-cart icon ဖြစ်ပေမဲ့ Buy Now/checkout (guest ဆို login) ကို တန်းသွား ([product_card.dart:275](../lib/shared/widgets/product_card.dart))။
- **U6** Error copy: server က `Product not found: <uuid>`၊ `Could not create order: <postgres message>` ပြန်ပြီး customer ဆီ ရောက် (`create-payment-intent/index.ts:323,375,624`)။ Signup rule 8+letter+digit ဖြစ်ပေမဲ့ error က "at least 6 characters" (`login_screen.dart:500`)။ `AuthException` အားလုံးကို "Your session expired" လို့ပြ (`error_message.dart:50`)။
- **U7** Offline နဲ့ app ဖွင့်ရင် cart hydrate fail → cart ဗလာ → item တစ်ခုထည့်တာနဲ့ save ထားတဲ့ cart ကို overwrite (data loss) — [cart_providers.dart:157](../lib/features/cart/presentation/cart_providers.dart)။
- **U8** Guest က heart နှိပ်ရင် `/login` ကို redirect မပါဘဲ ပို့ → login ပြီး product ဆီ မပြန် ([product_card.dart:415](../lib/shared/widgets/product_card.dart))။
- **U9** My Orders မှာ status tabs (To pay / To ship / To receive / Completed) မရှိ။

### Data / analytics

- **D1** Analytics က 90 ရက်စာ raw rows ကို client ဆွဲ → Supabase max rows 1000 မှာ ဖြတ်လို့ view/visit count အမှား ([analytics_repository.dart:19-45](../lib/features/admin/analytics/analytics_repository.dart))။ Server-side `count … group by day`။
- **D2** Bundled `.env` က prod URL ဖြစ်လို့ debug/QA run တိုင်း `app_visits` / `product_views` ကို prod ထဲ ရေး → owner analytics ညစ်။ Anon insert ဖြစ်လို့ spam လည်း ရ။

## P3 — အကြံပြုချက် / နောက်မှ

- **R1** Farm မှာ self-collect / pickup option (README က pickup ရှိသလို ရေးထားပေမဲ့ app မှာ မရှိ — business decision)။
- **R2** Commodity item တွေအတွက် "Back in stock — notify me"။
- **R3** Release AAB ထဲမှာ `.env` asset (pk_test + prod URL) ပါနေ → release မှာ `.env` ကို asset ကနေ ဖယ်ပြီး `--dart-define-from-file` တစ်ခုတည်း သုံး။
- **R4** Print tests ၄ ခုကို hermetic ဖြစ်အောင် (poppler မရှိရင် skip၊ real carrier label PDF ကို fixture နဲ့ အစားထိုး)။
- **R5** Hardening: unknown category → Koi (live-fish rule) အဖြစ် fallback (`product.dart`)၊ signup email ကို `@` ပဲစစ်၊ device clock မှားရင် shipping quote ကို expired ထင်ပြီး pay မရ။
- **R6** i18n (English သာ) — SG market အတွက် 中文 စဉ်းစားနိုင် (defer)။

## Recommended sequence

1. P0-1 promo lockdown (migration + RPC + client/server exact match) → P0-2 `.toLocal()` + test။
2. P1-2 address validation၊ P1-4 admin price validation၊ P1-8 pending/Pay-now။
3. P1-1 push deep link၊ A2 notification icon၊ P1-7 token handling။
4. P1-3 image sizing၊ P1-6 refresh/stale cache၊ A1 back handling။
5. P1-5 / D1 server-side revenue & analytics aggregates၊ P1-9 Crashlytics non-fatal။
6. iOS release prep: paid Apple account → I2 / I3 → I4 ပြန်ရိုက်စစ် → TestFlight။

## Explicit non-goals

Marketplace / multi-vendor၊ in-app chat system (WhatsApp လုံလောက်)၊ loyalty points၊ social feed၊ AI chatbot — P0/P1 မပြီးခင် မထည့်ရန်။
