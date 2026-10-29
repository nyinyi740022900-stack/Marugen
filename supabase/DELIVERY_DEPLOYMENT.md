# Delivery workflow deployment

For the subsequent TracX-only, actual-SKU-weight, SGD 50/50 checkout policy, also follow [SHIPPING_DEPLOYMENT.md](SHIPPING_DEPLOYMENT.md).

Apply `migrations/0057_delivery_fulfillment.sql` before deploying the updated functions and Flutter app. This migration is additive; it snapshots categories where the existing product proves them, classifies mixed/live-fish orders as shop delivery, and leaves unprovable legacy baskets requiring review. It also gives old manual tracking registrations an explicit `seventeentrack` provider.

Deploy these functions with the existing environment secrets:

- `create-payment-intent`
- `easyparcel-get-rates`
- `easyparcel-book-shipment`
- `easyparcel-refresh-status`
- `easyparcel-reconcile-shipment` (new, normal JWT authentication)
- `easyparcel-webhook` (retain existing `--no-verify-jwt` configuration)
- `track-register`
- `track-status`
- `track-webhook` (retain existing webhook authentication configuration)

Rates and booking now both require the identical `parcel` object containing positive numeric `weight_kg`, `length_cm`, `width_cm`, `height_cm`, and `collection_date` (`YYYY-MM-DD`, after the current Singapore date). Sender and receiver must have valid Singapore addresses. Older clients without parcel measurements fail safely. Checkout also validates Singapore delivery addresses and records trusted category snapshots.

Manual registration requires `confirmed_handover: true`. Its atomic database claim saves the confirmed tracking number and shipped status before contacting 17TRACK. A failed registration can be retried only with that same saved number; it cannot replace an EasyParcel claim. Refreshing 17TRACK status can complete a shipped order when the verified carrier response is Delivered, even if its webhook was missed.

EasyParcel booking retains paid/packing status until verified tracking reports collection (explicit codes 3, 4, 11) or delivery (5). Webhook payloads are hints: the server pulls authenticated tracking before advancing lifecycle status. Returned (6), scheduled (7), held (8), cancelled (0), and unknown codes do not prove collection.

An ambiguous booking never releases its claim or automatically books a replacement. `easyparcel_booking_state` becomes `needs_attention`; a `booking` claim becomes eligible for manual reconciliation after 15 minutes using `easyparcel_booking_started_at`. Staff must confirm the existing AWB from the EasyParcel dashboard and call `easyparcel-reconcile-shipment` with `order_id`, `tracking_number`, and `confirmed_existing_shipment: true`. The endpoint verifies tracking through the existing provider API and rejects different persisted shipment IDs when returned. It never replaces a saved AWB. There is no speculative shipment-ID recovery endpoint. If EasyParcel cannot verify the supplied number yet, retain the claim and resolve it with provider support.

For unknown legacy baskets with no tracking claim, staff can call authenticated RPC `confirm_shop_delivery(order_id)` to choose the safe hand-delivery path. The RPC allows paid/packing/shipped legacy orders and cannot select courier or alter an actual courier booking. Staff cannot edit the routing or courier metadata columns directly.

Local verification:

```sh
deno test supabase/functions/_shared/delivery_test.ts
bash supabase/tests/run_delivery_boundaries.sh
```

The PostgreSQL suite creates a disposable local cluster and does not use application credentials. No production migration, function deployment, billed booking, or live provider acceptance test has been performed as part of these code changes. Historical lifecycle statuses written by older booking code are retained; review old EasyParcel orders separately rather than automatically regressing their audited status history.
