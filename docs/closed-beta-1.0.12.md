# Closed beta 1.0.12 (17)

## Changes

- Fulfillment shows one pickup state and primary action. Wallet, diagnostic explanations and full tracking live behind Delivery details. Sample shipments cannot expose a shipping label or refresh as if they were live.
- Products and variants can save an optional complete packed length/width/height in cm. Partial, nonpositive and nonnumeric measurements are rejected by the form and database.
- Checkout uses the saved packed dimensions only for exactly one selected unit. Multiple units retain the existing weight-based behavior or explicitly configured shared parcel defaults; no automatic packing algorithm is claimed.
- Existing paid shipping snapshots, buyer charges and order addresses are not changed.

## Verification and deployment

- Full Flutter suite: 251 passed before the final disabled parent-field validation refinement; final delivery and product suite: 20 passed.
- Backend suite: 46 passed. Type checks passed for checkout-shipping-quote and create-payment-intent.
- Migration 0061 tested against a temporary PostgreSQL database: valid dimensions accepted; missing, zero, null and string values rejected for products and variants.
- Migration applied through authorized Supabase SQL editor; both JSONB columns verified live. No fabricated product measurements were entered.
- checkout-shipping-quote and create-payment-intent deployed using tested local bundles. Authentication settings preserved. Payment deployment initially blocked by approval-review usage limit; resumed after user instruction and completed.
- Signed production configuration AAB built; jar verified. Artifact and SHA256 recorded in output/releases/marugen-1.0.12-17-compact-fulfillment.json.

## Remaining delivery work

- Current sample order is not rebooked, paid or topped up. Receiver supplied by user: Johnny, 96627540, 14 Jalan Lekub, Singapore 808735. Actual packed kg and dimensions are still missing. No accepted financial/address snapshot was edited.
- Multiple-parcel labels are not implemented in this release. The current schema carries one shipment/AWB per order; a proper implementation needs parcel-level item allocations, independent tracking and labels, aggregate lifecycle rules and safe retry handling. User is choosing whether a split may incur additional seller-paid courier cost or must be restricted to quotes that do not increase total courier fees. Buyer must not be charged again after checkout.
- No claim that EasyParcel offers free additional parcel labels. Verify any multi-piece courier contract or quote before booking.

## Play and pickup handoff, 2026-10-23

Play validated version 17 (1.0.12); release saved in Alpha at 100% of existing testers, prior 16 excluded. Quick checks running; final send attempts closed the modal without a verified submitted state. Do not report in review. Both publishing page and EasyParcel form are marked handoff.

Live nonbinding website quote, 718788 → 808735 at 0.5 kg: Speedpost Economy pickup-to-door S$3.65, no paid add-ons. Receiver and product declaration filled from user instructions and order 19102026-0001 (item value S$1.00 confirmed in DB). Website reintroduces default 8×8×8cm after clearing dimensions. Actual packed measurements not supplied, so Checkout was NOT pressed; no parcel order, payment or pickup commitment created. Shipment label splitting remains unimplemented pending cost policy.
