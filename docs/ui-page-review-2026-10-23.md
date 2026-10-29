# Page-by-page UI review — Marugen — 23 October 2026

## Scope and evidence

This pass preserves the existing black, red and off-white `AppTheme`, navigation, business copy and purchase behavior. Marugen is a single-store retail app with unique live-fish stock and multi-quantity supplies. Stripe, courier booking and fulfillment remain separate integration concerns.

Evidence comes from the route inventory in `lib/core/router/app_router.dart`, customer/owner shell destinations, source inspection, and Flutter widget render/interaction tests using fixtures. Tests exercise real widgets with mocked data, compact phones, tablets, light/dark themes, enlarged text and keyboard insets where listed. These are **not** device acceptance tests, a live-backend audit, or screenshots of the production app.

The existing `App Screenshort/` assets were inspected as visual context. `Home.png` is a promotional composition rather than a current golden fixture, so it was not treated as proof of current layout. No committed screenshot/golden harness was found before this pass. An opt-in capture mode was then added to `test/ui_page_review_test.dart` and used for the bounded visual acceptance pass described below. There is still no full-device visual sign-off or production screenshot comparison. Widget layout assertions, hit-testing and the named fixture screenshots provide the evidence below.

Status meanings:

- **Fixed, tested:** a concrete defect was corrected and its stated fixture now passes.
- **Okay in tested cases:** the listed render/interaction checks passed; this is not a blanket accessibility or integration guarantee.
- **Source only / untested:** inspected, but the specified runtime behavior was not exercised in this pass.
- **Parallel review:** shipping/order work owned by the main task; this report does not claim its acceptance.

## Corrections made

1. **Owner More menu:** changed the fixed-height column to a scrollable menu. Settings remains reachable on a 320×200 surface with 2× text in both themes; selecting it still returns the existing destination index.
2. **Owner customer profile:** long saved-address labels and the Default badge wrap instead of competing in a single row. Order totals sit below status/date instead of squeezing the order title. Order-history tap feedback paints on an unobscured Material surface. Verified with long names/addresses and S$12345.67 at 320×640 and 820×1100, 2× text, both themes.
3. **Low-stock list:** restored visible Material tap feedback inside the existing colored card. The current Flutter SDK previously raised a hidden-ink assertion. Verified with a populated list at 320 pixels and 2× text in both themes.
4. **Review reply actions:** Cancel/Post Reply and Reply/Hide actions wrap to another line when necessary. The reply editor previously overflowed by 42 pixels at 320 pixels and 2× text. The Post Reply button is now reachable by scrolling; no review write is sent by the test.
5. **Owner Settings connection card:** placed Refresh below the connection status so it cannot squeeze the status text into an overflowing row. Reproduced 6.3-pixel overflow at 320 pixels and 2× text; verified the whole form can scroll to Save Settings above a 250-pixel keyboard inset in both themes.
6. **Owner Settings initial fetch:** a failed settings request now presents the existing retry error state instead of an endless loading spinner/unhandled error. A fake 503 response followed by a successful retry exercises recovery. Financial values and shipping-setting persistence are unchanged.
7. **FAQ:** the expansion tiles now paint tap feedback on Material within the existing rounded cards. This removes the hidden-ink assertion without changing questions, answers, colors or navigation. Verified expansion and scrolling on compact/tablet surfaces, 2× text and both themes.
8. **PDP purchase labels (visual finding):** the 320-pixel/2× capture showed “Add …” and “Buy …” despite no overflow assertion. At enlarged text on narrow screens, Add to Cart sits beside Chat and Buy Now occupies a second full-width row. Both labels remain complete in the confirmation capture; handlers and purchase intent are unchanged.
9. **Checkout promo Apply (visual finding):** the fixed 52-pixel height clipped Apply vertically at 2× text. Replaced the fixed height with a 52-pixel minimum, retaining the action and loading state. The confirmation capture shows the complete label.
10. **Checkout item summary (visual finding):** a long item name collapsed to “Pr…” beside price/remove at 320 pixels/2×. The compact enlarged-text layout now gives the title up to three lines and moves subtotal beneath quantity. The final fixture title is fully visible. Totals, shipping quotes, item removal and payment logic are unchanged.

## Customer pages

### Splash and setup-required

**Source only / untested.** Router startup/auth gates and setup-required surfaces were inventoried. Real cold start, missing configuration, session restoration and OS splash transition were not exercised by this pass.

### Login — `/login`

**Okay in tested cases.** `forms_responsive_test.dart` renders 320×600 at 2× text, both themes, with/without a 300-pixel keyboard inset. It scrolls to and hit-tests Log In above the keyboard. `theme_preference_test.dart` also verifies appearance-related customer account behavior. Existing login edits were preserved. Live password authentication and social-provider flows are untested here.

### Sign up — `/signup`

**Okay in tested cases.** Same compact/large-text/keyboard/theme render matrix in `forms_responsive_test.dart`. No new layout error found. Actual registration, email verification and server validation remain untested.

### Forgot password — `/forgot-password`

**Okay in tested cases.** Compact enlarged text and keyboard render coverage in `forms_responsive_test.dart`; `recovery_layout_test.dart` covers recovery layouts. Sending a reset email remains untested.

### Reset password — `/reset-password`

**Okay in tested cases.** Covered by the same recovery/form matrices. Router source preserves the password-recovery event route. Real email-link/session recovery is untested.

### Customer shell — Shop / Guide / Orders / Profile

**Okay in tested cases.** `customer_navigation_test.dart`, `ui_polish_test.dart`, `dark_customer_test.dart` and `theme_preference_test.dart` cover customer navigation, tablet rail positioning/stability, guest account access and selected-navigation contrast. A real OS notification prompt and launch promotion are untested.

### Shop/catalog — `/`, Shop destination

**Okay in tested cases.** `catalog_accessibility_test.dart` checks phone grids on Android/iOS themes, text scaling, aligned prices, long names, 48-pixel quick-cart targets, and recovery from no search matches. Existing grid/card hierarchy and purchase affordances were retained. Live image loading and backend pagination performance are untested.

### Product detail — `/product/:id`

**Fixed, tested.** See correction 8 and the PDP light/dark-large screenshots. Catalog tests exercise Buy Now intent without mutating the persistent cart. `responsive_followup_test.dart` renders related-product cards at enlarged text in both themes. `ux_review_regressions_test.dart` switches Overview/Reviews with reduced motion. Real gallery/video playback, WhatsApp, purchase eligibility and payment completion are untested in this UI pass.

### Cart — `/cart`

**Okay in tested cases.** `ux_review_regressions_test.dart` exercises remove/Undo lifecycle when leaving for checkout, and catalog purchase-intent checks preserve cart contents. Cart source retains empty-state shopping action and stock refresh. Server price/stock correctness is outside this page review.

### Checkout — `/checkout`

**Fixed, tested presentation; parallel shipping review.** See corrections 9–10 and checkout screenshots. `dark_customer_test.dart` renders checkout totals/cards using fixture shipping quotes and addresses. The visual pass changed only the summary-title/subtotal layout and promo Apply button sizing, with explicit coordination from the main task. Shipping/payment behavior remains owned by the main task. The live Stripe sheet, final charged total, tax, courier selection and order creation require separate integration acceptance.

### Order list, detail, success and tracking

**Parallel review.** Route and shell entries were inventoried. The existing `responsive_followup_test.dart` covers a scrollable compact confirmation with a large total; guest-order access is covered by `guest_account_consistency_test.dart`. Detail/tracking/status timeline code and shipping semantics were not changed by this pass.

### Wishlist — `/wishlist`

**Okay in tested cases.** `ux_review_regressions_test.dart` exercises retry after wishlist-ID failure followed by removal and the empty state. `guest_account_consistency_test.dart` checks guest prompts including compact enlarged text. Real account synchronization is untested.

### Profile — Profile destination

**Okay in tested cases.** `ui_polish_test.dart` checks the compact 2× guest profile, appearance sheet and working Log In destination in both themes. `theme_preference_test.dart` covers signed-in/guest appearance controls on Android/iOS and saved preferences. Live avatar upload, logout, deletion and notification-permission dialogs are untested.

### Address book and address form — Profile flow

**Okay for form rendering.** `forms_responsive_test.dart` verifies Save Address is reachable on 320×600 at 2× text above a 300-pixel keyboard, both themes. Backend saving/default-address switching and destructive deletion are untested.

### Guide and variety detail — Guide destination

**Okay in tested cases.** `ui_polish_test.dart` checks long variety labels at 320/720/820 widths, enlarged text and both themes; tablet columns, category filtering across resize and opening the selected detail are exercised. Live remote media remains untested.

### Notifications — `/notifications`

**Okay in tested cases.** `forms_responsive_test.dart` renders a populated 320×600 inbox at 2× text in both themes, including the Mark all read tooltip. Guest access is exercised by `guest_account_consistency_test.dart`. Push receipt and persisted read state are untested.

### FAQ and support — `/faq`

**Fixed, tested.** See correction 7. `ui_page_review_test.dart` expands a question and scrolls at 320×640 and 820×1100, 2× text, both themes. Contact-shop launches are untested; factual support copy was preserved.

### Terms — `/terms`

**Okay in tested cases.** `ui_page_review_test.dart` renders and scrolls terms at the same compact/tablet/theme/2× matrix. Existing terms edits were preserved; this is a layout review, not legal validation.

### Privacy — `/privacy`

**Okay in tested cases.** Same new compact/tablet/theme matrix plus existing `privacy_screen_test.dart` verifies compact privacy-request readability. Actual account/data-request handling is untested.

### Unknown route

**Source only / untested.** Router currently renders a simple Route not found message. A dedicated recovery/navigation design was not added during this scoped refinement.

## Owner pages

### Owner shell and More destinations — `/admin`

**Fixed, tested.** See correction 1. Home/Products/Orders and the existing More destinations remain unchanged. `ui_page_review_test.dart` directly tests the extracted menu at 320×200 and 2× text in both themes. The full owner shell was source-inventoried; it was not launched against a live owner session.

### Dashboard — Home destination

**Okay in tested cases.** `responsive_followup_test.dart` renders the owner dashboard with product/order fixtures, a large total and 2× text in both themes. Real-time counts and business correctness were not audited here.

### Products — Products destination

**Okay in tested cases.** `responsive_followup_test.dart` checks paginated grids at 320/360/390/820 widths and 1×/2× text, plus the search-result layout in both themes. Existing product-card actions were retained. Real product mutations and image loading are untested.

### Product editor — `/admin/products/new`, `/admin/products/:id`

**Parallel review.** Owned by the main task. Existing form tests in the combined suite cover compact category fields and Add Fish Option/price-field layout. Product editor and product model were not edited by this pass.

### Customer profile — `/admin/customers/:id`

**Fixed, tested.** See correction 2 and `ui_page_review_test.dart`. All displayed addresses/order history use fixtures; live customer lookup, privacy authorization and order navigation integration are untested.

### Orders, Payments and Delivery — Orders destination tabs

**Payments okay in tested render cases; delivery/order workflow parallel review.** `responsive_followup_test.dart` renders `AdminPaymentsPane` with a large total and 2× text in both themes. The existing `ui_polish_test.dart` delivery-card hierarchy check also passes in the combined suite. No financial/fulfillment actions or their backend truth were altered by this pass.

### Settings — More destination

**Fixed, tested.** See corrections 5–6. `admin_settings_layout_test.dart` initializes an isolated fake client, renders both themes at 320×640/2× text/keyboard inset, scrolls to Save Settings, and retries a simulated failed initial settings read. It does not save shop settings, connect accounts, launch OAuth or upload media.

### Low stock — `/admin/low-stock`

**Fixed, tested.** See correction 3. Populated list with long product title renders at 320 pixels and 2× text in both themes. Live inventory thresholds and product-edit navigation are untested.

### Top products — `/admin/top-products`

**Okay in tested cases.** `ui_page_review_test.dart` renders a long product name and a four-digit sold count at 320 pixels and 2× text in both themes. Sales-ranking calculations were not changed.

### Knowledge, Guides and Services — More / Knowledge tabs

**Okay for navigation/list fixtures; editing untested.** `admin_knowledge_image_failure_test.dart` verifies a failed remote variety image falls back while Hide from customers remains reachable. `ui_page_review_test.dart` additionally renders a populated variety list and switches to Guides and Services at 320 pixels/2× text in both themes. Full article/variety/service form editing and populated guide/service edge cases are not signed off in this pass.

### Promo codes — More destination

**Okay for list rendering.** `ui_page_review_test.dart` renders a populated list with a long code at 320 pixels and 2× text in both themes. Create/edit/date-picker validation and backend deletion are untested; discounts are unchanged.

### Reviews — More destination

**Fixed, tested.** See correction 4. The populated review list and opening/scrolled access to the reply form are tested at 320 pixels/2× in both themes. Posting/hiding reviews and verified-purchase authorization are untested by this UI-only pass.

### Analytics — More destination

**Okay in tested cases.** `admin_analytics_accessibility_test.dart` exercises Daily/Weekly/Monthly views at 320×640 and 800×1024, 2× text, both themes. Four-digit counts remain visible, with chart scrolling where required. Accuracy of real collected analytics is untested.

## Buy-path assessment

- **Catalog and PDP affordances: okay in covered fixtures.** Buy Now/cart intent and enlarged-card layout have meaningful interaction checks.
- **Cart: okay in covered interaction tests.** Restore lifetime and purchase intent are exercised.
- **Checkout/payment: partial.** Render checks pass; money, reservation, asynchronous payment and shipping acceptance belong to the main task and backend tests.
- **Orders/fulfillment: parallel review.** This UI refinement does not certify live order transitions.
- **Reviews/contact: partial.** Moderation form access is improved; live writes, eligibility and external contact are not exercised.

## Verification and limits

The combined 15-file Flutter suite passed **142 tests** after the UI fixes. A subsequent 28-test page matrix also passed, adding compact 2× owner Knowledge-tab scenarios in both themes. The settings-specific 3-test file passed, including failed-load recovery. Static analysis of all six changed UI files and both new test files reported **No issues found**; `git diff --check` passed. Tests use no live credentials and the Settings client is fake. No commit, push, release, deployment or external account write was performed by this UI subtask.

Remaining acceptance work: check the same pages on physical Android/iOS hardware with real images, screen readers, actual keyboard/IME, navigation gestures and OS dialogs; validate live sign-in/reset, address persistence, support/contact, review writes and Stripe/courier flows separately. Performance, every empty/error permutation, and every secondary edit dialog were not measured or exhaustively exercised. Source-only and partial statuses above are intentional limits, not passes.


## Rendered fixture acceptance pass

Actual PNG files are in `output/ui-page-review/`. Initial renders were inspected together as six contact sheets, including all 22 PNG views. A focused confirmation verified the changed PDP purchase labels, checkout name and Apply label. The capture suite passed 16 scenarios; focused checkout/catalog captures also passed after correcting the inherited test-font fallback and explicit title line count. This was a bounded pass, not a continuing design iteration.

Capture contexts:

- `light`: 390×844 logical pixels, 1× text, `AppTheme.light`.
- `dark-large`: 320×900 logical pixels, 2× text, `AppTheme.dark`.
- Installed `/System/Library/Fonts/SFNS.ttf` is loaded as the app's `.SF Pro Text`; Flutter's MaterialIcons font is loaded. Chip label styles with an unspecified family are mapped to the same SF face **only in the capture theme** because Flutter's test-default Ahem otherwise draws blocks. Production theme styles are unchanged by this harness mapping.
- Backend responses, order amounts, customer names and addresses are fixtures. Shop/PDP photos deliberately use the app's empty-image fallback; no actual remote-photo quality is certified.
- No device status bars, home indicator, native payment sheet, external app, system keyboard or push-permission dialog is rendered. The More capture shows the menu component in a Scaffold, not the full shell's modal placement. Keyboard-inset behavior is covered separately by the widget tests above.

Exact files:

- FAQ: `faq-light.png`, `faq-dark-large.png` — first question expanded; readable body, question wrapping and chevrons.
- Owner customer profile: `customer-profile-light.png`, `customer-profile-dark-large.png`, `customer-profile-orders-light.png`, `customer-profile-orders-dark-large.png` — initial profile and scrolled order-history views; address/default badge and large total remain readable.
- Owner More menu: `more-menu-light.png`, `more-menu-dark-large.png` — all five destinations and selected Knowledge state visible.
- Review reply: `review-reply-light.png`, `review-reply-dark-large.png` — editor plus complete Cancel/Post Reply/Hide labels; enlarged actions wrap.
- Settings: `settings-light.png`, `settings-dark-large.png`, `settings-connection-light.png`, `settings-connection-dark-large.png` — initial form and scrolled connection card; Refresh remains separate from connection status.
- Shop: `shop-light.png`, `shop-dark-large.png` — two-column normal-text cards and single-column enlarged cards with purchase affordance. Empty-image fallback is intentional fixture data.
- PDP: `product-detail-light.png`, `product-detail-dark-large.png` — overview, price/stock and sticky purchase actions; enlarged Add to Cart and Buy Now labels are complete.
- Checkout: `checkout-light.png`, `checkout-dark-large.png`, `checkout-summary-light.png`, `checkout-summary-dark-large.png` — initial address/item summary and scrolled promo/totals area. At enlarged text the long product name wraps, subtotal remains explicit and Apply is no longer vertically clipped.
- Contact sheets: `contact-light-1.jpg`, `contact-light-2.jpg`, `contact-light-3.jpg`, `contact-dark-large-1.jpg`, `contact-dark-large-2.jpg`, `contact-dark-large-3.jpg` combine the final PNG files for inspection.

Visual limits: long app-bar names and editable single-line fields may ellipsize or scroll, as expected; the screenshots do not establish live data freshness, actual phone safe areas, screen-reader order, native keyboard behavior or external integrations. Other pages retain their source/test statuses above and have no new screenshot acceptance claim.

To reproduce on this configured macOS machine: `UI_PAGE_CAPTURE=1 flutter test --no-pub test/ui_page_review_test.dart --plain-name capture`. Ordinary runs do not load machine-specific fonts, initialize the screenshot fake client or write capture files.


Post-visual verification: the targeted customer/catalog/checkout regression suite passed **93 tests** after the purchase-page corrections. Static analysis of the capture harness, PDP and checkout reported **No issues found**; `git diff --check` passed. The final catalog screenshot was checked after the capture-only chip font mapping and shows readable All/Koi/Arowana/Fish Food labels. The render artifacts occupy approximately 2.4 MB.


## Final acceptance follow-up

The original source-only/partial entries above describe the initial pass. The subsequent customer, owner-editor and product/order gaps are covered by [final acceptance](ui-final-acceptance-2026-10-23.md) and its linked reports. Full regression verification now passes 389 tests; Android and iPhone simulator guest navigation and Stripe SDK initialization pass. External operations and physical-device limits remain explicitly separate.
