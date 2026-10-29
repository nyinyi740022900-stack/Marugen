# Closed beta 1.0.13 (18)

## Changes

- Owners can allocate purchased quantities into real packed parcels, enter each box's kg/dimensions and pickup date, and obtain separate labels and tracking.
- Customer shipping paid at checkout remains fixed. Current courier total and seller contribution require explicit owner approval tied to the exact current quote before booking.
- Atomic database guards prevent duplicate plan claims, concurrent single/split bookings, and changes to submitted boxes. Uncertain outcomes recover through verified shipment details rather than resubmission.
- Customer tracking shows each parcel and aggregate progress. Partial delivery never labels the entire order delivered. Sample labels are hidden.
- Page review fixed the owner More menu, customer-profile wrapping, low-stock tap feedback, review actions, settings retry/connection layout, FAQ tap feedback, product purchase labels and checkout product/promo layout.

## Verification

- Full Flutter suite: 288 passed. Flutter analysis: no issues. Diff whitespace check passed.
- Backend shared suite: 76 passed. Parcel SQL boundaries and real concurrent session race tests passed in isolated PostgreSQL.
- 22 UI fixture screenshots and six contact sheets cover eight page types in light and dark/enlarged text. See `ui-page-review-2026-10-23.md` for exact page coverage and limits.
- Signed production AAB built and signature verified. SHA256: `18925276682f5b9dddfe5b1c7cc026886766fc86f1ea6fd22928d254313c88c7`.
- Migration 0062 applied live. Verified order_parcels exists, RLS enabled, customer mutation RPC denied and service-role mutation allowed.
- New order-parcels, easyparcel-refresh-status and easyparcel-webhook deployed live. Existing function authentication settings preserved.

## Limits and release state

- Actual courier payment, collection and live multi-parcel booking have not been performed. No wallet top-up or customer recharge occurred.
- Legacy sample order 19102026-0001 was not reset or rebooked; actual packed dimensions remain unverified.
- Native device safe areas, keyboard behavior, live media and Stripe sheet completion are not fully device-accepted by the fixture UI review.
- Play version 18 (1.0.13) saved in closed Alpha with existing tester/country scope. Publishing overview verified **Changes in review** and **Running quick checks**. Submission accepted; not yet available to testers. Evidence: `output/split-parcels/beta18-in-review.png`.

## Live parcel handoff — 23 October 2026

User confirmed actual packed measurements: 0.5 kg, 19 × 7 × 7 cm. Prepared exactly one unpaid EasyParcel SG cart item, reference EC-2610-A7GAY, for Marugen order19102026-0001. Recipient Johnny /96627540 /14 Jalan Lekub,808735. Speedpost Economy door pickup quote S$3.65, no paid add-ons. Same-day cutoff1:45pm passed at2:36pmSG, so selected next weekday26October2026. Cart state verified Pending payment; wallet/freecredit bothS$0.00. No Checkout/payment/top-up was executed and no live AWB or pickup confirmed. Await approval of S$3.65 expenditure; do not create a duplicate cart item. Evidence output/split-parcels/live-pickup-pending-payment.png. Original paid order snapshots remain unchanged.

Carrier steering: user requested TracX instead of SingPost. Existing cart EC-2610-A7GAY switched to TracX Logis, no additional parcel created. TracX quote list S$4.05; final checkout Instant Pay S$4.60 beforeGST /S$5.01 includingGST, exceeding previously approvedS$4.89. No payment submitted. Saturday24October date update was asynchronous; persisted cart eventually verified2026-10-24. TracX service info: nextbusinessday collection before9:30pm booking cutoff, pickupMonday–Saturday8am–11pm, estimate1–2workingdays aftercollection. Await approval of new final amount; do not pay against old SingPost approval.

## Verified live booking linked — 23 October 2026

User completed EasyParcel payment. Connected SG account10947427 showed invoice/order EI-2610-XVXMG and TracX pickup scheduled2026-10-24. Downloaded AWB QSP223261096.pdf (copied to output/split-parcels) contains original app order reference19102026-0001, recipientJohnny808735 and correct item. Observed official label URL ES-2610-5UF8T/7633145. Public tracking and authenticated tracking_status API both verified Schedule In Arrangement; API returned matching AWB QSP223261096, shipmentES-2610-5UF8T, code7, HTTP200.

Applied guarded one-off supabase/ops/20261023_link_verified_tracx.sql through authorized SQL editor. Old tracking EPSAMPLE17924122984637797262 /shipmentES-2610-CXZDP /needs_attention replaced with verified AWB, shipment, official label, booked and code7. Atomic checks require exact old claim, authenticated API evidence and no conflicting parcel/other order. All non-tracking order fields asserted unchanged; original customer charge and purchase-time address remain preserved. Actual shipping label has Johnny14JalanLekub808735. No new courier booking, payment or customer recharge during reconciliation.

Verified saved app order after commit. Existing refresh/webhook resolve live AWB/shipment; no sample identity remains on current order. Physical courier handover has NOT happened yet. Device app should reload to retrieve the new row; live on-device rendering not observed in this session. Evidence: live-tracx-pickup-confirmed.png and app-live-tracking-linked.png in output/split-parcels.
