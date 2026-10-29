# Closed beta 1.0.24 (29)

Submitted to Closed testing — Alpha on 2026-10-30, full rollout. It replaced 28 (1.0.23) while that was still in review (Play Console restarted the review), so testers receive everything from `closed-beta-1.0.23.md` plus the parcel fixes below. Built from main at 10e4593.

## Parcel booking recovery

Order 29102026-0003 (two parcels, same address) stayed on "Booking in progress" and never appeared in EasyParcel:

- EasyParcel did not confirm parcel 1, so parcel 2 was correctly never sent. The function discarded EasyParcel's reason.
- The 0063 tracking guard treated the function's own failure write (no provider status code) as a stale provider event and reverted `state` to `booking`.

Fixes (migration 0070, `order-parcels`):

- The guard skips boxes with no provider identity, so failed boxes show "Booking not confirmed by EasyParcel" / "Not booked — an earlier parcel failed".
- `booking_error` stores EasyParcel's short status + message (never the request body), shown to staff only.
- "Retry booking" (after staff confirm EasyParcel has no shipment) returns an unidentified failed plan to draft for a fresh quote and approval. Boxes EasyParcel identified can never be rebooked.
- "Ship as one parcel" drops an unsubmitted split. EasyParcel bills every box separately, so one box to one address is usually cheaper (this order: S$3.79 × 2 split).
- Split orders show the real parcel total and shop share instead of the checkout single-parcel quote.

The order was refunded by the owner before rollout. Its two parcels stayed in `booking` because 0070 ran 14.5 minutes after the quote expired (inside the 15-minute in-flight window); a one-off repair statement was handed to the owner.

## Production backend

Deployed: migration 0070 (column and both functions verified present), `order-parcels`.

## Verification

- Flutter: 496 of 500 passed; `flutter analyze` clean. The 4 failures are print acceptance tests that need `pdftoppm` (poppler) and local `output/` PDFs not present on this machine.
- Split-parcel suite: 9 passed, including retry rules and the parcel total.
- Deno parcel suite: 14 passed, including EasyParcel rejection reasons and timeouts; `order-parcels` type-checks.
- Isolated PostgreSQL parcel suite and race tests passed, including the failure write, reset rules and discard.
- Not yet verified: a real split booking against EasyParcel after this fix.

## Release artifact

`output/releases/marugen-1.0.24-29-parcel-recovery.aab`, 85.2 MB, `jar verified` (upload key). SHA-256: `720d13067ec19999a397a195189d1649f783080ad29c6e892017e7fa95641e09`. Play Console: 0 devices lost.
