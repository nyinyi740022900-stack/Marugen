# Final UI acceptance — 23 October 2026

The user accepted Android emulator and iPhone simulator acceptance for this pass; physical-device testing is deferred. Existing Marugen visual direction and checkout/shipping business rules are preserved.

## Outcome

- Full Flutter regression suite: **389 passed**, exit 0. Full analysis: **No issues found**. Whitespace verification passes.
- Customer startup/recovery/auth/profile/address/notifications/wishlist follow-up: 40 focused tests. Owner variety/guide/service/promo editors: 44 focused tests. Product/order forms: 15 focused tests. These focused counts are included in the 389 total.
- Checkout Android minimum tap target and labeled-control checks: two theme scenarios pass; Remove item now meets the standard target size.
- Android Pixel 7 emulator API 37 and iPhone 17 Pro simulator iOS 26.4 both pass native guest navigation and Stripe SDK initialization. Public catalog reads are real; all writes are blocked by the integration harness. SDK initialization does not charge or open a payment sheet.

## Material fixes

Compact layouts and 2× text now retain readable form errors, promo selections, product fields, order totals and invoice/contact actions. Narrow order timelines use vertical stages. Setup instructions and logout confirmation scroll. Unknown routes offer recovery. Address retry remains clear of the floating action button.

Owner editors display local validation/save errors, handle old promo expiry dates, and retain created IDs on partial-save retries. Auth screens block duplicate requests and safely handle completion after navigation. Product saves prevent edits during writes and stop subsequent operations after disposal. These asynchronous cases use controlled fake services.

## Page evidence

- Initial page inventory and catalog/checkout/owner secondary surfaces: [page review](ui-page-review-2026-10-23.md).
- Customer secondary pages and async auth: [customer follow-up](ui-final-customer-flows.md).
- Owner content and promo editors: [owner follow-up](ui-final-owner-forms.md).
- Product editor, owner orders/detail and timeline: [product/order follow-up](ui-final-product-order.md).
- Actual rendered fixture captures: `output/ui-page-review/`, `output/ui-final-customer/`, `output/ui-final-owner/`, `output/ui-final-product-order/`.
- Native confirmation captures: `output/ui-final-native/android-confirmed/` and `output/ui-final-native/ios-confirmed/` (eight PNGs each).

Native focus screenshots do not show an OS software keyboard because the integration runner suppresses it. Keyboard clearance is verified with explicit widget-test insets. The confirmed directories use the accurate `native-login-focused-input.png` name. Remote catalog photos are visible in native captures; owner media uses fixtures.

## Scope limits

No physical phone, screen-reader traversal, OS permission/image-picker acceptance, live OAuth/reset email, successful owner media upload/save or new live Stripe charge is claimed. These checks must remain distinct from layout and simulated interaction acceptance. Native owner-session navigation and every possible empty/error permutation are not exhaustively certified.

Existing live shipping evidence remains separate: paid TracX AWB QSP223261096 is linked to order 19102026-0001 with pickup scheduled for 24 October. A scheduled pickup is not proof of collection. This UI pass does not book or pay for another shipment.

## Beta delivery

Production-configured Android closed beta **1.0.14 (19)** builds successfully (84.4 MB); `jarsigner -verify` returns exit 0 and `jar verified`. Artifact: `output/releases/marugen-1.0.14-19-final-ui.aab`. SHA-256: `2c551c6ce0f34289c9be36edd8bbb6e23bc6dfd308fcac53e898d889cf994987`.

Uploaded to the existing Closed testing — Alpha track with only bundle 19 included. Saved rollout to existing testers and submitted the change. Play Console visibly confirms **Changes in review — 19 (1.0.14)**. Quick checks are still running; approval and availability to testers are not yet claimed. Proof: `output/releases/beta19-in-review.png`. Testers and country configuration were not changed.
