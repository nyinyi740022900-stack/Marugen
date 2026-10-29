# Split parcels and page quality

Approved in the chat: the owner allocates one order across actual packed boxes, with a separate label and tracking for each. Customer checkout shipping charges never increase. Any additional courier cost is shown to the owner and requires explicit approval before booking. No live shipment/payment is performed as part of development.

## Delivery behavior

Owner opens Split into parcels for a paid/packing courier order with at least two units and no existing shipment claim. Allocate every purchased unit exactly once across 2–20 boxes; enter actual kg, length, width, height and future Singapore pickup date for each. Product packed dimensions and weight can prefill a single-unit box; multi-item boxes require actual measurements. Existing accepted order shipping snapshots remain immutable.

Save an atomic plan, quote each parcel using eligible door-to-door pickup services and display aggregate actual SGD cost, fixed buyer share and resulting seller cost. Owner approval binds to the exact current aggregate quote. Changed/expired quotes, concurrent plans, or existing claims block booking. Claim before provider submission. Partial provider success is preserved; uncertain or failed submissions are never blindly retried. An unpaid booking is labeled payment required, not awaiting confirmed pickup. Sample AWBs never expose a shipping label.

Each parcel owns its immutable booking identity, AWB, label URL and verified tracking. Customer order detail shows Parcel N of M and per-parcel progress with no extra charge. Parent delivered requires all parcels delivered. Partial collection/delivery remains visible. Terminal cancelled/refunded orders cannot be revived. Legacy single shipment orders retain their existing safe path; sample/uncertain claims are not reset.

## Data and security

New order_parcels relation with order-level locking, exact line-item allocations and server-owned quote/booking fields. Customer read is restricted to their own order; only owner/staff can invoke planning actions. No client mutation of courier records or accepted payment/price snapshots. An owner-approved maximum binds the provider operation. No speculative payment API is added.

## UI quality work

Preserve incumbent red/black/off-white design, routes and content. Audit every customer/admin route using real rendered fixtures where available, including 320px, large text, dark mode and keyboard. Fix material task, overflow, interaction, contrast and hierarchy defects. Record untested runtime boundaries honestly; do not imply every platform/hardware was exercised.
