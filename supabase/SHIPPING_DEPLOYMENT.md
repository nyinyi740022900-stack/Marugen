# Shipping policy activation

Production shipping schema and ten shipping/delivery functions were deployed on 2026-10-20 through the authorized Supabase browser session. No real payment or billed shipment was performed. The updated app still requires installation/store rollout; see the completed activation evidence below.

## Policy

- Courier: TracX Logis only. Native SGD provider totals are used directly. MYR totals are converted with a dated Frankfurter/ECB MYR→SGD rate; other currencies fail safely. Provider `total_amount` includes provider taxes/fees.
- Buyer pays half in integer SGD cents; seller covers the remainder, including an odd cent. Example: SGD 4.05 = buyer 2.02 + seller 2.03. The buyer share is added once after merchandise GST. Both shares remain on the order and invoice.
- Live fish, including mixed baskets, use shop delivery. The buyer pays zero delivery. No courier quote or booking is requested. The shop's internal delivery expense is not estimated or recorded as a fictitious courier quote.
- Courier weight = each selected product/variant's saved `shipping_weight_kg` × ordered quantity, summed on the server. Selected variants require their own weight. There is no fixed 1 kg fallback. Client-supplied weights and amounts are ignored.

## Activation order

1. Apply `0057_delivery_fulfillment.sql`, then `0058_shipping_finance.sql`. Coordinate with any later pending migrations; do not deploy only the Flutter app against the old schema.
2. In the product editor, verify kg per unit for every courier product and every selectable variant. Exact labels such as `500g` and `1.5 kg` migrate automatically; ambiguous labels remain unset. Product names and unspecified weights are never guessed. Missing weight prevents courier checkout with an actionable message.
3. Verify the shop's Singapore sender address/phone/postcode and EasyParcel OAuth connection in Settings. Confirm the connected account offers TracX for the actual route and weight. The observed portal wallet was SGD 0.00; ensure sufficient credit before a real paid booking.
4. Optional standard dimensions may be configured only when they actually apply to all courier parcels. Otherwise leave all three blank: checkout requests a weight-based quote. EasyParcel requires positive actual packed dimensions at booking. Staff can enter missing dimensions then; weight and any quoted dimensions remain locked. The server re-quotes and blocks booking if service/source price/accepted SGD total differs. Resolve the shipment as seller-paid delivery if packaging changes the charge; never silently recharge the buyer.
5. Deploy `checkout-shipping-quote` (new, JWT authenticated), `create-payment-intent`, `easyparcel-get-rates`, `easyparcel-book-shipment`, `track-register`, and the delivery functions listed in `DELIVERY_DEPLOYMENT.md`, preserving existing webhook verification configuration. Publish the updated Flutter client together with this release.
6. Run staging acceptance with real configured SKU weights and a Stripe test payment: coupon, included/excluded merchandise GST, cart/address changes, expired quote, cancel/retry, and paid retry. Confirm the accepted amount equals the checkout display. Inspect the order/invoice split. Test a live-fish mixed basket with buyer shipping zero. Complete one real TracX booking only when authorized and funded; verify handover/tracking separately.

## Guards and limitations

Quotes expire after 15 minutes and bind account, cart options, address, promo, prices, SKU weights and settings. Checkout persists the accepted service, parcel, currency conversion and split as immutable server-owned fields. Retry reuses an existing payment rather than charging again. Paid bookings preserve their original FX snapshot even after five days; new MYR quotes require a fresh rate. No alternative carrier is selected when TracX is unavailable.

Legacy orders without a prepaid quote cannot create a new billed EasyParcel shipment through this flow. Arrange seller-paid delivery separately. Existing historical carrier/tracking records remain available for fulfillment audit.

## Local verification

```sh
flutter test
flutter analyze
deno test --allow-env supabase/functions/_shared/shipping_api_test.ts
deno test supabase/functions/_shared/shipping_finance_test.ts supabase/functions/_shared/delivery_test.ts
bash supabase/tests/run_shipping_finance_boundaries.sh
```

The adapter test uses a mocked EasyParcel response and verifies the outgoing actual-weight request, carrier filtering, MYR conversion and exact split. It does not submit or purchase a shipment. A nonbinding portal quote was inspected in Chrome: TracX Logis was available for the demonstrated Singapore route; portal prices are not hardcoded into checkout.

Provider references: [EasyParcel OpenAPI](https://github.com/easyparcel/OpenAPI), [Frankfurter provider-specific API](https://frankfurter.dev/).


## Completed production activation — 2026-10-20

The user continued the shipping rollout and confirmed that Uni-Light Nitrifying Bacteria 500ml, PetFran Anti Chlorine 2L, and the Hikari Koi Food Container each weigh **2 kg**. Those three base products and both liquid variants were updated accordingly. The exact kg/g variant labels were migrated, leaving all **48 courier variants with known positive kg** and **zero standalone courier products missing weight**.

- Applied 0057 and 0058 together in one transaction and registered their exact source in migration history, leaving the already deployed 0059 refund migration intact. Compatibility was tested with 0059 applied first in a disposable database, including refund and stock/cancellation checks.
- Deployed the ten functions in `/private/tmp/marugen-shipping-rollout/function-manifest.json`; existing sources were backed up before replacement. Shared local modules were bundled, preserving HTTPS package imports and existing function authentication settings.
- New checkout quote and recovery functions retain gateway JWT verification. Existing provider webhooks retain their prior gateway mode and internal source/signature checks.
- All eight user-authenticated shipping/payment endpoints returned HTTP 401 with the handler's `Unauthorized` response to a project-anonymous JWT. This also verifies their deployed bundles boot, without creating payments or shipments.
- EasyParcel webhook rejects an untrusted request with HTTP 403. 17TRACK intentionally responds HTTP 200 with `received:false,error:invalid signature` to avoid retries; it does not process the event. Validation checks the body as well as status.
- Deployed checkout quote, payment, and booking source were read back through the dashboard and matched the reviewed bundles exactly.
- Sender name/phone/address are present, postcode has six digits and country is SG. EasyParcel connection exists; its access token is expired while refresh token remains valid. The existing refresh helper renews access during an authenticated quote; a successful live API token refresh was not claimed or demonstrated.
- A separate nonbinding portal quote for 2 kg, Singapore 718788→059893, showed TracX Logis available in SGD. The portal supplies its own default dimensions; those are not copied into product settings. Portal prices/discount tiers are not hardcoded as app shipping charges.
- Production order status counts remained paid 1, packing 1, shipped 2, cancelled 7, delivered 7. No production shipping quote/order/payment/booking was fabricated for acceptance testing. Existing historical orders retain zero buyer shipping and cannot be retroactively charged.
- Production evidence, source backups, migration package and manifests are in `/private/tmp/marugen-shipping-rollout/`. User-facing screenshots are `output/releases/shipping-live-weights-20261020.png` and `shipping-functions-20261020.png`.

### Remaining device/store acceptance

Use the newly prepared **1.0.6+11** production-configured signed app release. Earlier installed apps do not request the required quote, so courier checkout requires updating them. No Play Store/App Store publishing or device installation has been performed. A signed APK is a build/signature check, not proof of payment-sheet acceptance on the customer's device. Live checkout and billed booking remain untested: the portal wallet has SGD 0.00; a real shipment requires credit and an explicitly authorized order. Test calculations and mocked adapter coverage are distinct from live provider/payment acceptance.


### Release artifacts verified

- `output/releases/marugen-1.0.6-11-shipping.apk`: signed production Android installer; APK manifest confirms `com.marugen.marugen_app`, version 1.0.6, versionCode 11. APK signature verified with the existing Marugen certificate. Bundled `.env` configuration was checked for server-only credential names/prefixes; none detected.
- `output/releases/marugen-1.0.6-11-shipping.aab`: signed Play Store upload artifact; JAR signature verification passed. Not uploaded or published.
- SHA-256/size manifest: `output/releases/marugen-1.0.6-11-shipping.json`.
- Final server test suite: 54 tests passed (`/private/tmp/marugen-shipping-final-deno-tests.log`). Existing app suite: 236 passed; static analysis clean. Release APK and AAB builds both passed.
- No Android device was attached when checked; device payment-sheet/live checkout acceptance remains outstanding. No charges, paid bookings, top-ups or store publishing were performed.


### Closed beta submission — 2026-10-20

The user subsequently requested closed beta. Version 1.0.6+11 was uploaded to the existing Alpha track and submitted as the single release change. Play Console confirms **Changes in review**. Existing tester/group/country configuration retained. Approval and tester availability remain pending; no Production release. See `docs/closed-beta-1.0.6.md`.

### Checkout simplification and TracX identity fix — 2026-10-20

The user corrected **Uni-Light 500ml to 0.5 kg**, superseding only that item's earlier 2 kg confirmation. Applied an atomic parent/variant update scoped to the known IDs and 500ml label. Public product API readback confirms both are 0.5 kg; PetFran 2L and Hikari container remain 2 kg each. The equivalent guarded replay script is `supabase/ops/20261020_unilight_500ml_weight.sql`. Existing server calculations sum trusted SKU kg × quantity.

A nonbinding EasyParcel request returned **TracX Logis Pte. Ltd**, service **EP-CS0GN**, MYR 17.73 for 2 kg on both Singapore 718788→718788 and 718788→059893. The old exact carrier allowlist omitted the dot in `Pte.` and discarded the valid quotes. Added only the observed exact legal name; other carriers remain excluded. A regression test failed before the change and passed afterward. The live Frankfurter/ECB rate (2026-10-19, 0.31329 SGD per MYR) converted this observed quote to SGD 5.55: buyer 2.77, shop 2.78. This demonstrates calculation with actual observed provider metadata and live FX; it is not an authenticated end-to-end checkout or a guaranteed future rate.

Deployed `checkout-shipping-quote`, `easyparcel-get-rates`, and `easyparcel-book-shipment` through the existing dashboard account after the CLI account returned 403. Each staged editor showed the corrected allowlist, and a freshly loaded function list confirmed all three new revisions. Public-anonymous probes returned handler HTTP 401 Unauthorized for all three, confirming boot and authentication guards without creating orders or buying shipments. Existing gateway authentication was retained. Evidence is in `/private/tmp/marugen-delivery-fix/`.

The updated customer checkout hides carrier and contribution details, displays the buyer's SGD delivery fee, and shows a Singapore-calendar estimated arrival range from configured lead days after a valid quote. These are calendar-day estimates, not guaranteed carrier dates. Live-fish/mixed baskets retain free arranged shop delivery. Quote failure displays an unavailable state and a working Retry delivery action without enabling payment; a stalled client request times out after 30 seconds. Customer order summaries show only the buyer's fee; staff retain the full allocation.

Verification: **240 Flutter tests passed**, static analysis clean, and **30 shipping/delivery server tests passed**. Light/dark checkout previews are in `output/delivery-review/`. Signed **1.0.7+12** AAB built and JAR signature verified; artifact and SHA-256 manifest are in `output/releases/`. Build version overrides were used; pubspec remains at the prior submitted version. No live payment or booked shipment was created. Authenticated device checkout/payment and actual carrier handover remain acceptance steps.

## 2026-10-20: all couriers in SGD

User explicitly requested all available couriers in S$, superseding TracX-only. Migration 0060 applied and recorded with source MD5 75f18b3d16c18199633d4abfa8d53736. RLS remains enabled; authenticated clients cannot SELECT shipping_quotes. Updated checkout-shipping-quote, easyparcel-get-rates, easyparcel-book-shipment and track-register were deployed.

Owner lists all normalized SGD rates; paid orders only enable their immutable accepted service/amount/parcel. Other quotes and legacy orders without prepaid shipping are reference only. New checkout sets all_couriers=true and chooses the cheapest quoted door pickup / door delivery service. Older installed clients retain compatible results. Allocation and source currency remain validated server-side. No paid carrier booking was executed.

Validation: Flutter 240, focused UI 31, Deno 32 and SQL boundaries passed. Final checkout anonymous handler probe returned 401 Unauthorized.
