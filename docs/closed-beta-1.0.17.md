# Build 1.0.17 (22), superseded before submission

This intermediate bundle was uploaded and validated in a draft, then removed from the release before submission when the user clarified that printing requires custom dimensions and an explicit one-copy source selection. It was never submitted to review. The replacement release is recorded separately.

Orders and fulfillment now use pull down at the top to refresh the carrier and then reload the authoritative order lists. Circular tracking refresh controls were removed. Failed provider requests preserve the stored result and show a retry message. Product cards use consistent cart/favourite glyphs and touch areas, with a separate price row. Product detail tabs have consistent insets; the related section is now Recommended for you. Fulfillment print actions are grouped below delivery information.

Shipping labels, packing slips and invoices open a PDF preview before printing or saving. Shipping label options include the original carrier PDF, an A4 sheet with a 4 x 6 area and nine placement choices, and actual 4 x 6 paper. Original mode preserves the PDF bytes. Fitted modes rasterize the complete source page at 300 dpi without cropping. The real TracX document contains two copies; both are retained, so fitting onto smaller paper reduces their size. Physical printer output and barcode scanning are not established by these checks.

## Tracking incident and live repair

EasyParcel returned an older Schedule In Arrangement summary dated 23 October while its carrier history contained Pickup Done on 24 October 11:04:02 Singapore time. Shipment details independently returned Collected. The parser now selects the newest dated evidence for the exact AWB. Migration 0063 adds atomic, timestamp-aware tracking updates and a custody progress watermark on orders and parcels. Older refreshes cannot overwrite newer evidence; a later hold cannot erase verified collection. Delivered and returned remain distinct.

The user explicitly approved the production schema/backfill/guard changes after automatic approval review initially rejected their broad scope. Migration 0063 and the five affected function bundles were deployed to the existing production project. The guarded repair for order 19102026-0001 used the authenticated provider response for QSP223261096 / ES-2610-5UF8T. It verified that every non-tracking field stayed unchanged and deliberately attempted the older scheduled event in a later request. That attempt was rejected and the row stayed Pickup Done, code 3, progress 1, event 2026-10-24T03:04:02Z. No booking, payment, address or financial mutation was made. SQL: `supabase/ops/20261024_verify_live_pickup_progress.sql`; screenshot: `output/tracking-regression/live-pickup-progress-proof.png`.

## Verification

- Full Flutter suite: 417 passed. Final print-action cleanup also passed the 16-test delivery suite.
- Flutter analysis: no issues.
- Deno tracking/delivery/parcel/diagnostic tests: initially 47 passed; an explicit two-parcel distinct-label test brings the current suite to 48 passed.
- Isolated PostgreSQL boundary and race suite passed, including stale tracking snapshots, direct writers, parcel aggregate lifecycle, returned evidence and permissions.
- Light/dark and large-text widget captures inspected; actual carrier PDF fitted onto A4 and 4 x 6 was rendered and inspected. Catalog captures use image placeholders.

Native physical-device acceptance and physical printing were not performed in this pass. Production-configured release build and Play submission status are recorded below once verified.

The signed production build completed successfully (84.7 MB); Android Studio's bundled jarsigner returned exit 0 and `jar verified`. Build uses APP_ENV=prod, the expected Supabase production project and a live Stripe publishable key (verified without exposing values). Artifact: `output/releases/marugen-1.0.17-22-delivery-print-ui.aab`. SHA-256: `ffef43050354d7c9a66f4c7924303bba046b04d86a7f52fbdd9c694835f6291a`.

Final independent review found one important exception: fresh Returned events after collection/transit were blocked by the custody watermark. A regression reproduced it before the fix. Migration 0064 allows fresh return code 6 while retaining progress and terminal-return protection; single-shipment atomic and split-parcel race tests pass. It was applied live and a read-only check confirmed fresh_return_allowed=true and stale_pickup_rejected=true while the protected order remains Pickup Done. No other important findings were reported in the bounded review.
