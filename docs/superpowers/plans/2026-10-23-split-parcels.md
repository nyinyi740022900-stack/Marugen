# Split parcels implementation plan

**Goal:** Separate labels and progress for actual boxes without charging the customer again.
**Architecture:** Atomic parcel plans and server-owned quote/booking records, integrated into the incumbent fulfillment and customer detail pages.
**Stack:** Flutter/Riverpod, Supabase/PostgreSQL, Deno, EasyParcel OAuth.
**Spec:** ../specs/2026-10-23-split-parcels-design.md

## Constraints

No commits/push, no real payment/booking during development. Preserve all existing work. Buyer shipping snapshots are immutable. Approval binds the exact fresh quoted total; uncertainty retains the claim.

## Tasks

- [ ] Backend worker: implement migration 0062, order-parcels endpoint and tested orchestration. Allocation invariant: `sum(parcel.items[item.id].quantity) == item.quantity` for every purchased line, with no foreign/duplicate lines. Claim plan atomically before submission. Verify exact per-parcel shipment/tracking identities and aggregate lifecycle. Test SQL RLS, allocations/races, stale quote/cap, partial success, sample/unpaid and partial delivery.
- [ ] Root: add OrderParcel and order item IDs; nested repository relation, parcel planning repository/API, accessible allocation form, owner quote review and single explicit booking confirmation. Consumer contract: `order-parcels` with `list`, `save_plan`, `quote`, `book`, `refresh`. Customer detail renders independent parcel tracking.
- [ ] UI worker: page-by-page review and narrow fixes outside delivery-owned files, with rendered overflow/state/theme tests and evidence log.
- [ ] Root integration: inspect diffs, run whole Flutter suite/analyzer plus backend/SQL boundary tests, render representative new UI, resolve material failures in one bounded batch. Deploy migration and affected functions preserving auth configuration. Build production-configured signed beta and verify Play state. Report any missing provider/live verification separately.
