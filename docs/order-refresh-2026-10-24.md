# Deleted orders still visible — 24 October 2026

A new production read after the user's report returns exactly one order: 19102026-0001, shipped. The deleted 19 orders have not reappeared on the server. Evidence: `output/backups/order-count-rechecked-2026-10-24.png`.

The owner shell retains its tabs in an IndexedStack. The normal All list uses a long-lived paged provider; Payments uses a separate unbounded provider. Selecting Orders previously did not refresh either provider, and the Orders AppBar offered no refresh action. External SQL deletion cannot invalidate these existing in-memory lists. A full process restart reloads the current server data on the installed version.

Source correction: selecting the primary Orders destination refreshes the existing shared admin order providers, and the Orders AppBar now has a labeled Refresh orders action. The existing helper updates paged All, searched All/Payments/dashboard and fulfillment data. No deletion, payment, stock or delivery mutation is performed by refresh. This source correction requires a future app build; it is not included in previously built beta 20.

Delivery follow-up: the user requested the update. Production-configured beta **1.0.16 (21)** now contains this correction and is uploaded and confirmed **Changes in review** in Play Console; see `closed-beta-1.0.16.md`. Availability still depends on Google approval.

Two failing regression cases reproduced the missing action with externally deleted fixture orders. After correction, refreshing removes the deleted row from the paged list and refreshes the cached unbounded result, retaining the surviving order and producing zero repository writes. The combined product/order/delivery/page suite passes **63 tests**, including existing tab-spacing checks. Two light/dark rendered cases pass and were inspected. Full analysis finds no issues; whitespace check passes. Captures: `output/ui-final-product-order/order-refresh-Brightness.light.png` and dark counterpart. Navigation invokes the same tested refresh helper; a full live owner/device session was not exercised.
