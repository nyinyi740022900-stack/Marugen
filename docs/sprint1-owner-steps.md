# Sprint 1 — Owner လုပ်ရမယ့်အဆင့်များ (19 Nov 2026)

> **21 Nov 2026 update:** အဆင့် ၁၊ ၂၊ ၃၊ ၅၊ ၇ (0077–0080 နဲ့ function redeploy) ကို Claude က production မှာ လုပ်ပြီး စစ်ဆေးပြီးပါပြီ (အသေးစိတ် `docs/closed-beta-1.0.28.md`)။ ကျန်တာ: ၄ (refund order stock)၊ ၆/၈ (Play Console upload နဲ့ device စမ်း)၊ ၉ (content)၊ EasyParcel webhook log။

Sprint 1 code က ရေးပြီး test pass ပြီးသားပါ။ အောက်ကအဆင့်တွေက owner ကိုယ်တိုင် လုပ်ရမယ့်အရာတွေပါ။
အစီအစဉ်အတိုင်း လုပ်ပါ: **၁ → ၂ → ၃ → ၄ → ၅**။

- [x] ၁။ Production မှာ pre-flight query တွေ run
- [x] ၂။ Migration 0077 တင်
- [x] ၃။ တင်ပြီးနောက် စစ်ဆေး
- [ ] ၄။ အရင် refund လုပ်ပြီးသား order တွေရဲ့ stock ကို လက်နဲ့စစ်
- [x] ၅။ `config.toml` ထဲက ခန့်မှန်းထားတဲ့ function ၆ ခုကို dashboard နဲ့ တိုက်စစ်
- [ ] ၆။ App 1.0.28 ထုတ်ပြီး device ပေါ်မှာ စမ်း

---

## ၁။ Pre-flight (read-only၊ ဘာမှမပြောင်းပါ)

Supabase dashboard → SQL editor မှာ တစ်ခုချင်း run ပါ။ မထင်မှတ်တဲ့ရလဒ်ထွက်ရင် 0077 မတင်ခင် Claude ကို ပြပါ။

```sql
-- 1. Owner: table နဲ့ function တွေက postgres ပိုင်ရမယ်
select c.relname, c.relowner::regrole, c.relrowsecurity
  from pg_class c where c.oid = 'public.order_number_counters'::regclass;
select p.oid::regprocedure, p.proowner::regrole, p.prosecdef, p.proconfig
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('assign_order_number','claim_promo_redemption','release_promo_redemption',
                     'cancel_stale_pending_orders','reconcile_pending_orders',
                     'restore_stock_on_cancel','prevent_role_self_escalation');

-- 2. Cron job တွေက အပေါ်က owner (postgres) နဲ့ run ရမယ်
select jobname, username, schedule, command, active from cron.job;

-- 3. 0077 က အစားထိုးမယ့် function နှစ်ခုက repo (0036, 0020) နဲ့ တူရမယ်
select pg_get_functiondef('public.prevent_role_self_escalation()'::regprocedure);
select pg_get_functiondef('public.restore_stock_on_cancel()'::regprocedure);
select tgname, pg_get_triggerdef(oid) from pg_trigger
 where tgname in ('orders_restore_stock_on_cancel','trg_prevent_role_self_escalation');

-- 4. လက်ရှိ staff/owner စာရင်း (မသိတဲ့လူ ပါ/မပါ စစ်)
select id, email, role from public.profiles where role <> 'customer' order by role, email;

-- 5. မပို့ခင် refund လုပ်ပြီးသား order တွေ (0077 က ဒါတွေရဲ့ stock ကို မထိပါ → အဆင့် ၄)
select o.order_number, o.refunded_at, h.from_status, i.product_name, i.quantity,
       p.category, p.stock_quantity, p.is_sold
  from public.orders o
  join public.order_status_history h on h.order_id = o.id and h.to_status = 'refunded'
  join public.order_items i on i.order_id = o.id
  left join public.products p on p.id = i.product_id
 where o.status = 'refunded' and h.from_status in ('paid','packing')
 order by o.refunded_at desc;

-- 6. Bucket ထဲမှာ ပုံမဟုတ်တဲ့ဖိုင် / 10 MB ကျော်ဖိုင် ရှိ/မရှိ
select metadata->>'mimetype' as mimetype, count(*),
       max((metadata->>'size')::bigint) as largest_bytes
  from storage.objects where bucket_id = 'product-images' group by 1 order by 2 desc;
select id, file_size_limit, allowed_mime_types from storage.buckets where id = 'product-images';

-- 7. Table နာမည်အသစ် လွတ်နေရမယ် (NULL ထွက်ရမယ်)
select to_regclass('public.order_stock_restorations');
```

## ၂။ Migration 0077 တင်

`supabase/migrations/0077_sprint1_security_fixes.sql` ဖိုင်တစ်ခုလုံးကို SQL editor မှာ paste လုပ်ပြီး run ပါ။
Transaction တစ်ခုတည်းဖြစ်ပြီး နှစ်ခါ run လည်း ပြဿနာမရှိပါ။

## ၃။ တင်ပြီးနောက် စစ်ဆေး

```sql
-- နှစ်ခုလုံး relrowsecurity = true ဖြစ်ရမယ်
select relname, relrowsecurity from pg_class
 where relname in ('order_number_counters','order_stock_restorations');

-- row တိုင်း false ဖြစ်ရမယ်
select r, f, has_function_privilege(r, f, 'execute')
  from unnest(array['anon','authenticated']) r,
       unnest(array['public.claim_promo_redemption(uuid)','public.release_promo_redemption(uuid)',
                    'public.cancel_stale_pending_orders()','public.reconcile_pending_orders()']) f;
```

ပြီးရင် test order တစ်ခု ဝယ်ကြည့်ပြီး order number ထွက်/မထွက် စစ်ပါ။

## ၄။ အရင် refund order တွေရဲ့ stock

Query 5 ကထွက်တဲ့ order တစ်ခုချင်းအတွက် admin app မှာ product ကိုဖွင့်ပြီး stock / "sold" အခြေအနေ မှန်/မမှန် ကြည့်ပါ။
ပစ္စည်းက ဆိုင်မှာ တကယ်ရှိနေသေးရင် stock ပြန်တိုး ဒါမှမဟုတ် koi ကို "available" ပြန်လုပ်ပါ။

## ၅။ config.toml စစ်

Dashboard → Edge Functions မှာ အောက်က ၆ ခုရဲ့ "Verify JWT" က **ဖွင့်ထား (true)** ဟုတ်/မဟုတ် ကြည့်ပါ။
မတူရင် `supabase/config.toml` ကို ပြင်ဖို့ Claude ကို ပြောပါ။

- `easyparcel-get-rates`
- `track-register`
- `easyparcel-refresh-status`
- `order-parcels`
- `delete-account`
- `stripe-refund`

**သတိ:** `supabase config push` ကို လုံးဝမ run ပါနဲ့။ ဒီဖိုင်မှာ function setting ပဲပါလို့ live auth / storage setting တွေ default ပြန်ဖြစ်သွားပါမယ်။

## ၆။ 1.0.28 ထုတ်ပြီး device စမ်း

0077 တင်ပြီးမှ app ထုတ်ပါ (အရင်ထုတ်ရင်လည်း အလုပ်လုပ်ပါတယ်၊ ဒါပေမယ့် 0077 တင်ပြီး 1.0.27 သုံးနေတဲ့ admin က extension မပါတဲ့ပုံတင်ရင် ပယ်ခံရနိုင်ပါတယ်)။

Device ပေါ်မှာ စမ်းရန်:

- Checkout ဖွင့်ထားပြီး app ကို ၁ နာရီကျော် background ထား၊ ပြန်ဖွင့်ရင် checkout မှာပဲ ရှိနေရမယ်။
- Stripe test mode မှာ ငွေချေ → "Payment received. We're confirming it with the bank…" ပြပြီး paid ဖြစ်သွားရမယ်၊ cart ရှင်းရမယ်။
- Airplane mode နဲ့ app စဖွင့် → splash မှာ Retry / Sign out ပြရမယ်။
- Admin မှာ HEIC ပုံနဲ့ gallery ပုံ upload။
- Admin Products မှာ "Koi" chip နှိပ်ပြီး Home ပြန်သွား → Products count နဲ့ Low Stock မပြောင်းရ။

## ၇။ Sprint 3 backend (0077 ပြီးမှ)

- [ ] ၇.၁ `supabase/migrations/0078_sprint3_hardening.sql` ကို SQL editor မှာ run (GST snapshot column၊ index ၉ ခု၊ admin RPC ၂ ခု၊ EasyParcel token lease)
- [ ] ၇.၁.၁ `supabase/migrations/0079_easyparcel_refresh_lease_release.sql` ကိုလည်း run (0078 ပြီးမှ)
- [ ] ၇.၂ Edge Function တွေ redeploy
- [ ] ၇.၃ Test order တစ်ခု ဝယ်ပြီး စစ်

**အစီအစဉ် မလွဲပါနဲ့: 0078 အရင်၊ function redeploy နောက်မှ။** ပြောင်းပြန်လုပ်ရင် checkout က 500 error ပြပါမယ်။

Redeploy လုပ်ရမယ့် function တွေ (`easyparcel-status` ကလွဲပြီး အားလုံး)။ Claude ကို "function တွေ deploy လုပ်ပေး" လို့ပြောရင် CLI နဲ့ လုပ်ပေးနိုင်ပါတယ် (`supabase login` အရင်လုပ်ထားရမယ်၊ `supabase projects list` နဲ့ Marugen account ဟုတ်/မဟုတ် အရင်စစ်)။

- JWT မစစ် (`--no-verify-jwt`): `stripe-webhook`, `track-webhook`, `easyparcel-webhook`, `easyparcel-oauth-callback`, `reconcile-pending-orders`
- JWT စစ်: `cancel-order`, `checkout-shipping-quote`, `create-payment-intent`, `delete-account`, `easyparcel-book-shipment`, `easyparcel-get-rates`, `easyparcel-oauth-start`, `easyparcel-pickup-diagnostics`, `easyparcel-reconcile-shipment`, `easyparcel-refresh-status`, `order-cancellation`, `order-parcels`, `resume-order-payment`, `send-order-notification`, `stripe-refund`, `track-register`, `track-status`

တင်ပြီးနောက် စစ်ရန်:

```sql
-- GST snapshot ပါလာရမယ် (order အသစ်မှာ NULL မဟုတ်ရ)
select order_number, total, gst_percent, gst_included_in_price, gst_amount_cents
  from public.orders order by created_at desc limit 3;
-- Admin အနေနဲ့ app ထဲက Payments နဲ့ Top Products ဖွင့်ကြည့်ပါ
```

- Stripe dashboard → Webhooks မှာ delivery အောင်မြင်နေ/မနေ ကြည့်ပါ။
- EasyParcel webhook အစစ်တစ်ခု ရောက်ပြီးရင် Dashboard → Edge Functions → `easyparcel-webhook` → Logs မှာ `[easyparcel-webhook] source-ip` လိုင်းကို ကူးပြီး Claude ကို ပြပါ (IP စစ်ဆေးမှုကို အပြီးပြင်ဖို့ လိုပါတယ်)။
- EasyParcel နဲ့ parcel တစ်ခု book လုပ်ကြည့်ပြီး label (AWB) ပေါ်လာ/မလာ စစ်ပါ။

## ၇.၅။ Monitoring (0080)

- [ ] `supabase/migrations/0080_ops_monitoring.sql` ကို run (0079 ပြီးမှ)။ ၁၅ မိနစ်တစ်ခါ စစ်ပြီး owner/staff ရဲ့ app notification ထဲ သတိပေးချက် ထည့်ပါတယ် (push မပါသေး၊ in-app ပဲ)။
- သတိပေးမယ့်အရာ: ၄၅ မိနစ်ကျော် pending ဖြစ်နေတဲ့ ငွေချေမှု၊ refund fail / ၂၄ နာရီကျော် pending၊ payment စစ်တဲ့ cron job မအလုပ်လုပ်၊ courier booking ၃၀ မိနစ်ကျော် ပြဿနာရှိ၊ EasyParcel connection သက်တမ်းကုန်။
- တင်ပြီးရင် `select * from public.ops_monitor_findings();` နဲ့ လက်ရှိတွေ့ရှိချက် ကြည့်နိုင်ပါတယ် (ဘာမှ မရေးပါ)။
- သတိ: 0080 က payment cron function `reconcile_pending_orders()` ကို အစားထိုးပါတယ် (HTTP call က အတူတူ၊ request id မှတ်တာပဲ ထပ်တိုး)။

## ၈။ Sprint 2 + 3 app ကို device ပေါ်မှာ စမ်းရန် (1.0.28)

- [ ] Fresh install → ပထမဆုံး order ဝယ်ပြီးမှ "Get a message when your order ships." dialog နဲ့ notification ခွင့်တောင်းရမယ်၊ ဒုတိယ order မှာ ထပ်မမေးရ။
- [ ] Sign-up အစစ် → "Confirm your email" ပြ၊ Resend email ရောက်၊ Go to Log In အလုပ်လုပ်။
- [ ] Guest အနေနဲ့ Profile → FAQ & Support၊ Send feedback (WhatsApp/email မှာ version ပါလာရမယ်)၊ Terms၊ Privacy။
- [ ] Admin → More → Home Banners မှာ slide ၂-၃ ခု ထည့် ("A product" ရွေးပြီး link ချိတ်)၊ customer home မှာ ပေါ်/မပေါ်၊ pull-to-refresh နဲ့ update ဖြစ်/မဖြစ်။
- [ ] Slide မရှိချိန် app စဖွင့် → home screen မခုန်ရ။
- [ ] Live fish page မှာ "Free hand delivery in Singapore" ပြရမယ်။
- [ ] 0078 တင်ပြီးနောက် order အသစ်ရဲ့ invoice PDF မှာ GST line မှန်/မမှန်၊ order အဟောင်း invoice လည်း အရင်အတိုင်း ဖြစ်ရမယ်။
- [ ] Admin Payments နဲ့ Top Products ကိန်းဂဏန်း (0078 မတင်ခင်ရော တင်ပြီးရော အလုပ်လုပ်ရမယ်)။
- [ ] Admin မှာ sold toggle၊ review Hide၊ variety hide/delete ကို မြန်မြန် နှစ်ချက်နှိပ်ကြည့်။
- [ ] Video ပါတဲ့ live fish page → gallery ရဲ့ ဒုတိယ slide မှာ "Play video" ပေါ်၊ နှိပ်ရင် ဖွင့်၊ swipe လုပ်ရင် ရပ် (YouTube link ရော ဖိုင် link ရော စမ်း)။
- [ ] Product page၊ product card၊ Services က contact ခလုတ် → WhatsApp / Phone / Email ရွေးစရာပေါ်ပြီး message ကြိုဖြည့်ထားရမယ် (guest ရော login ဝင်ထားသူရော)။
- [ ] Admin Orders မှာ tab နှစ်ခုပဲ (All / Fulfillment) ရှိရမယ်၊ order card ပေါ်မှာ "Paid S$…" လိုင်း၊ order detail ရဲ့ PAYMENT မှာ Payment ID နှိပ်ရင် copy ဖြစ်ရမယ်။
- [ ] Admin Home မှာ "Collected through Stripe" card ပေါ်ရမယ်။
- [ ] Customer app စဖွင့်ရင် promo popup မတက်ရ။
- [ ] Live fish တစ်ကောင်ကို edit → Age ဖြည့်၊ Certificate photo တင် (iPhone HEIC ပုံနဲ့ပါ စမ်း) → product page မှာ Age နဲ့ "View certificate" ပေါ်ရမယ်။

## ၉။ Content ဖြည့်ရန် (code မလို)

- [ ] အရင် daily promo popup ပုံကို ဆက်ပြချင်ရင် Home Banners မှာ slide အဖြစ် ပြန်ထည့် (popup က ဖြုတ်လိုက်ပြီ၊ ပုံဟောင်းက သိမ်းထားဆဲ)။
- [ ] လက်ရှိ live fish တွေမှာ Age နဲ့ certificate ပုံ ဖြည့်။
- [ ] Home Banner slide ၂-၃ ခု ထည့်။

## သိထားရန်

- Owner က app ထဲကနေ staff ခန့်လို့ မရသေးပါ၊ အရင်လို SQL editor ကနေပဲ ခန့်ရပါမယ်။
- Courier ယူသွားပြီး tracking မ update ခင် အပြည့် refund လုပ်ရင် stock ပြန်တိုးသွားပါမယ် (ရှားပါတယ်၊ refund မလုပ်ခင် ပစ္စည်းဆိုင်မှာရှိ/မရှိ ကြည့်ပါ)။
