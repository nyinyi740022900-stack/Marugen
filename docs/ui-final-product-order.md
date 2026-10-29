# Product and owner order final UI acceptance — 23 October 2026

This scoped pass preserves Marugen's existing AppTheme, product persistence, order authority, financial values and fulfillment semantics. It extends `docs/ui-page-review-2026-10-23.md` with real-widget fixture checks of product editing, owner order actions, shared order detail and the status timeline. It does not certify a live owner session or a successful backend mutation.

## Fixed defects and evidence

- **Product read failure:** a 503 originally escaped `_loadExisting` and left the editor spinning. The failing regression now passes with a readable Retry state; retry loads the existing product. A missing product has its own Product not found state, preventing accidental edits to a blank existing-product form. Loading completes safely when the screen has been disposed. Delete product now has an accessible tooltip.
- **Product form readability:** weight guidance previously truncated to one line. Product and variant helper copy now wraps; compact enlarged food/accessory variants place price, kg and stock on separate full-width rows. Long editable option labels retain their input and horizontal text-field scrolling. Partial packed dimensions and negative weight produce inline errors; correcting all three dimensions and entering positive kg makes the form valid.
- **Owner order cards:** a 320-pixel/2× fixture reproduced a 337-pixel total-row overflow plus ellipsized Contact Buyer and Print Invoice labels. The total wraps and compact actions stack at full width with content-sized buttons and a 48-pixel minimum target. The owner tabs scroll to show full labels instead of squeezing them into thirds.
- **Shared owner order detail:** a synthetic owner session reproduced 227-pixel address-header overflow, 22-pixel item-row overflow and 139-pixel total-row overflow. The address/Copy header and total wrap; item subtotal is beneath the description, and the saved item title can wrap completely. The invoice action stays complete and reachable.
- **Pickup timeline:** the enlarged horizontal layout broke Awaiting pickup into a 203-pixel-tall letter column. A targeted failing readability test now passes after narrow/enlarged layouts switch to vertical stages. Existing recorded-event selection, stage order and pickup/transit semantics are unchanged. Terminal cancelled/refunded notices also allow their text to wrap.

## Covered interactions

`test/final_product_order_forms_test.dart` adds 14 scenarios: failed/missing product reads; compact product validation, long variants, failed save/input retention, and keyboard Save access in both themes; dismissing product deletion without a write; owner order cancellation dismissal without a write; simulated owner status failure leaving its retry action enabled; owner shared detail pickup/action rendering; compact timeline readability and cancelled notice wrapping.

The host is 320×900 logical pixels at 2× text using AppTheme light/dark. Product editing additionally applies a 250-pixel keyboard inset and asserts the entire Save button can scroll above it. Product requests use a fake HTTP client at a `.invalid` endpoint; POST attempts deliberately fail. Order action repositories are in-memory fixtures. Deletion/cancellation confirmations are dismissed. Nothing is written to the live backend, Stripe or a courier.

The shared detail uses the requested tracking number **QSP223261096** with entirely synthetic order/customer/address data. Its **To Be Collected / Waiting for courier pickup** tracking state and **Awaiting courier pickup** order label are fixture values. This is presentation evidence; it does not establish that shipment's current carrier status. Refresh tracking, invoice sharing, contact launching and real refunds were not invoked.

## Capture evidence

Actual PNG files are in `output/ui-final-product-order/`. One initial batch and one confirmation batch were inspected. The confirmed timeline usability defect received an explicitly authorized, narrowly scoped additional two-theme timeline confirmation; no further broad polish pass was run.

- `owner-actions-Brightness.{light,dark}.png`: full Contact Buyer/Print Invoice labels, wrapped total and horizontally scrollable tabs/filters.
- `owner-cancel-Brightness.{light,dark}.png`: real owner cancellation dialog, dismissed without a write.
- `product-delete-Brightness.{light,dark}.png`: real product deletion dialog with long name, dismissed without a write.
- `product-load-retry.png`: readable failed initial product read with Retry.
- `product-variant-fields-Brightness.{light,dark}.png`: compact long-label/price/kg/stock/packed-size form view. Single-line editable labels scroll naturally.
- `product-variant-Brightness.{light,dark}.png`: scrolled dimensions/size options/Save view with keyboard inset. This capture is positioned at the focused field and shows the Save text at the viewport edge; the stronger subsequent test asserts the entire Save button is reachable above the inset.
- `owner-detail-pickup-Brightness.{light,dark}.png`: requested AWB rendered with synthetic pickup state and invoice action.
- `owner-detail-actions-Brightness.{light,dark}.png`: full invoice action and tracking card.
- `owner-detail-address-Brightness.{light,dark}.png`, `owner-detail-items-Brightness.{light,dark}.png`: wrapped address/Copy and complete item/total. These two scroll positions coincide because the compact remaining content fits in one viewport.
- `timeline-pickup-Brightness.{light,dark}.png`: final vertical pickup timeline. **Use these for final timeline acceptance.** Earlier detail screenshots intentionally retain the pre-fix horizontal timeline that exposed the defect.

Capture-only setup loads the installed SF Pro face and MaterialIcons; chip styles with no explicit family use SF Pro in the capture theme to avoid Flutter's Ahem fixture font. Production type styles are preserved. Keyboard captures simulate the available inset; they do not draw the OS keyboard. No live photos, real device safe areas, screen reader output or native external sheets are certified by these PNGs.

## Verification

Final async follow-up adds a fifteenth scenario: while a product write is held pending, edits are absorbed; after disposal, completion does not issue further writes or touch disposed form controllers. The editor retains a created product ID for a partial-save retry, snapshots images before awaiting, and guards subsequent variant operations with mounted checks. The corrected controlled-response harness and all 15 focused tests pass within the final **389-test** full run. This does not certify a successful live product write.

- Combined six-file product/form/order/fulfillment regression suite: **69 passed**.
- Focused timeline confirmation capture: **2 passed**.
- Scoped analysis of the four production UI files and new harness: **No issues found**.
- `git diff --check`: passed.

Reproduce the regular suite with `flutter test --no-pub test/final_product_order_forms_test.dart test/forms_responsive_test.dart test/variant_weight_label_test.dart test/order_detail_authority_test.dart test/delivery_workflow_test.dart test/product_shipping_weight_test.dart`. The opt-in capture flag is `FINAL_PRODUCT_CAPTURE=1`; ordinary tests do not load machine fonts or write screenshots. The timeline-only confirmation uses `--plain-name 'compact timeline'`.

Physical Android/iOS owner-session acceptance, assistive technology, real IME interaction, successful product saving/media picking, live invoice/contact launching, live tracking refresh and fulfillment/payment transactions remain outside this fixture-only subtask. No commits, pushes, releases or external account writes were performed.
