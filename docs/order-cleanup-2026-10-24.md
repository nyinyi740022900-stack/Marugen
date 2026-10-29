# Confirmed order cleanup — 24 October 2026

The owner explicitly authorized keeping real order 19102026-0001 and deleting every other app order, then confirmed the exact counts before execution.

Executed `supabase/ops/20261024_cleanup_test_orders.sql` against production project gexgcwdkbeythrnqmihe. The transaction locks the affected tables, checks the explicit 19-order allowlist and approved dependent counts, and compares the protected order and every dependent record before/after deletion. Any mismatch raises an exception and rolls back.

Deleted: 19 orders, 33 order items, 26 status-history records and 23 order notifications. No target parcel, refund or promo-redemption rows existed. No external Stripe/EasyParcel operation, refund, booking cancellation or stock adjustment was performed.

A fresh independent read confirms one order remains: 19102026-0001, shipped, tracking QSP223261096. The remaining order, one item, three order notifications and two status-history records exactly match the local pre-delete backup, including the complete financial fields. Empty parcel/refund/promo arrays also match.

Private local backups and verification: `output/backups/orders-before-cleanup-2026-10-24.json`, `orders-after-cleanup-2026-10-24.json`, and `order-cleanup-verification-2026-10-24.json`. These files are excluded from Git. Proof: `output/backups/order-cleanup-completed-2026-10-24.png`.
