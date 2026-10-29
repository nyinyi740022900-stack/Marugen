# Closed beta 1.0.18 (23)

Includes the pull-to-refresh, tracking regression protection, catalog refinement and PDF preview work documented in `closed-beta-1.0.17.md`, plus the user's clarified custom printing requirements. Intermediate bundle 22 was removed from the draft before review submission.

## Printing

The carrier's real source PDF contains two copies of the same AWB, not two parcel bookings. Print preview now offers explicit Whole page / Top half (1 copy) / Bottom half (1 copy) choices. Selecting a half from Original mode switches to A4 with a visible explanation. Original mode preserves the complete original bytes and copies.

Users can enter label width and height in millimetres on A4, adjust horizontal/vertical position and edge inset, or enter custom paper dimensions. 4 x 6 remains a preset. Finite/range/fit validation blocks invalid output. The selected source pixels are proportionally fitted without stretching or rebuilding barcodes. Crop results are cached; position sliders rebuild on release, with print/share disabled during the drag. Print/share use the current preview bytes.

Actual protected-order carrier output was rendered and inspected as one top copy at 180 x 128 mm on A4 and one bottom copy on 180 x 128 mm custom paper. Full address, barcode, QR code and footer remain present. Examples: `output/pdf/carrier-preview-top-copy-custom-a4.pdf` and `output/pdf/carrier-preview-bottom-copy-custom-paper.pdf`. Physical printer and scanner acceptance remain untested.

## Split parcels

Controlled tests cover exact item allocation, distinct tracking identities/label URLs for two booked parcels, owner approval of additional cost, unchanged prepaid buyer shipping, duplicate booking claims, partial booking failures and partial delivery. A two-label owner widget fixture exposes a print action per parcel. No new multi-parcel live booking or payment was created for this verification; the protected real order remains its existing single shipment.

## Verification

- Full Flutter suite: 421 passed; full analysis: no issues.
- Focused print/split-parcel suite: 18 passed.
- Backend tracking/delivery/parcel/diagnostic suite: 48 passed.
- Isolated PostgreSQL boundary/race suite passed, including fresh returns after custody, terminal-return protection, stale-event rejection and preserved customer shipping charges.
- Independent bounded reviews found one important return-state exception, fixed by migration 0064 and verified again; the custom printing follow-up review found no release-blocking issues.

Live tracking migrations 0063/0064 and five affected functions are deployed. Real order 19102026-0001 remains Pickup Done, code 3, progress 1; a stale scheduled update is rejected. A read-only live predicate check also confirms fresh returns can be accepted. No order financial/address or payment/booking change was made.

## Release artifact

Production-configured Android bundle built successfully (84.8 MB), version 1.0.18/code 23. Signature verification returned exit 0 and `jar verified`. Artifact: `output/releases/marugen-1.0.18-23-custom-print-tracking.aab`. SHA-256: `fab80af622f3f9257b16b54e27b731ea2df3eb4e5688cb8d982c50afc3c23217`. Only this replacement bundle is intended for the existing Closed testing — Alpha track.

Additional local digital barcode verification used macOS Vision on the actual rendered carrier outputs. Both custom one-copy renders yielded one Code128 and one QR detection, with the expected AWB readable. The complete 4 x 6 two-copy example yielded two of each. This is digital image decoding, not physical print/scan acceptance. Evidence: `output/pdf/barcode-validation.txt`.

## Play status at handoff

Bundle 23 was uploaded, validated, previewed and saved to the existing Alpha track at100% of its existing testers, with bundle21 excluded. Google quick checks completed successfully and the console says the changes can now be sent for review. Sending the confirmation repeatedly closed the dialog but did not persist a submission: a fresh reload still shows Changes not yet submitted for review. Both browser locators and direct tab input were attempted. Native Chrome fallback could not access an input window (`noWindowsAvailable`). Do not claim In review or tester availability. The final Send changes for review dialog is open for the user to complete manually. Proof: `output/releases/beta23-ready-for-review.png`.

## Confirmed after user completed handoff

The user reported done. A fresh inspection of Publishing overview confirms **Changes in review**, **Your changes are now in review**, and the single **Closed testing — Alpha / 23 (1.0.18) / Start full rollout** change. Submission is confirmed; Google approval and tester availability are still pending. Proof: `output/releases/beta23-in-review.png`.
