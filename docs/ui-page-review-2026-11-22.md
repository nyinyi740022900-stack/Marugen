# Page-by-page review — every screen — 22 November 2026

Branch `product-card-redesign` (= `main` after PR #5, plus the button-free product card, commit 918144b). Read-only: no code changed. Method: four parallel reviewers (customer browse, customer purchase/account, admin operations, admin catalogue/content) read every screen file in full against the earlier audits; the lead re-checked the top findings in code. Nothing was run on a device this time (the iPhone simulator would not install the app), so layout findings come from code and two widget-test probes.

Status (later on 22 Nov): every P0 and P1 below is fixed on `product-card-redesign` (uncommitted at the time of writing) except the invoice's "TAX INVOICE" title, which waits for the owner to confirm the shop's GST registration. P2 items are open. Backend part is migration 0081 (not applied to production yet). Tests: `flutter test` 958 passed, 4 skipped; SQL suites and `deno test` pass. Checked on a Pixel 7 emulator: empty Koi state, cart button on the product page, cart. Hosted `docs/terms.html` updated to match the in-app Terms.

## Verdict per page

49 pages: 14 Good, 22 Minor issues, 13 Needs work.

### Customer — browse

| Page | File | Verdict | Reason |
|---|---|---|---|
| Splash | `lib/core/router/splash_screen.dart` | Good | Loading, Retry / Sign out on profile failure |
| Customer shell | `shop/presentation/customer_shell.dart` | Good | Four tabs, no launch popup or prompt |
| Shop, card, grid, banners | `shop_screen.dart`, `product_card.dart`, `hero_banner_carousel.dart` | Minor | New card sound; empty Koi/Arowana chips read as a filter error |
| Product page, video, reviews | `product_detail_screen.dart`, `reviews_section.dart` | **Needs work** | No cart entry, no way out of loading/error, review row overflows |
| Guide | `knowledge/presentation/knowledge_screen.dart` | Minor | Growth-stage cards clip text |
| Services | `services/presentation/services_tab.dart` | Minor | Bare spinner, pager has no indicator |
| Wishlist | `wishlist/presentation/wishlist_screen.dart` | Minor | Remove has no undo |
| Notifications | `notifications/presentation/notifications_screen.dart` | Good | (customer side) |
| FAQ and support picker | `support/faq_screen.dart` | Minor | Copy still says WhatsApp; nothing on live fish |
| Terms | `legal/terms_screen.dart` | **Needs work** | States a cancellation right the app does not give |
| Privacy | `legal/privacy_screen.dart` | Good | |

### Customer — purchase and account

| Page | File | Verdict | Reason |
|---|---|---|---|
| Cart | `cart/presentation/cart_screen.dart` | Minor | GST/delivery footer can be untrue; "+" silent at max |
| Checkout | `orders/presentation/checkout_screen.dart` | **Needs work** | Back allowed while paying |
| Payment helpers | `orders/utils/payment_*.dart` | Good | |
| Order success | `orders/presentation/order_success_screen.dart` | Minor | Unrouted dead code |
| Orders list | `orders/presentation/orders_screen.dart` | Good | |
| Order detail | `orders/presentation/order_detail_screen.dart` | **Needs work** | Dead end after slow confirmation; no GST line |
| Cancellation panel | `orders/presentation/order_cancellation_panel.dart` | Good | (customer side) |
| Login | `auth/presentation/login_screen.dart` | Minor | Error not announced; raw auth text can show |
| Sign up | `auth/presentation/signup_screen.dart` | **Needs work** | Existing email gets a false "we sent a link" |
| Forgot password | `auth/presentation/forgot_password_screen.dart` | Good | |
| Reset password | `auth/presentation/reset_password_screen.dart` | Minor | No exit; no new-password autofill |
| Profile | `auth/presentation/profile_screen.dart` | Minor | Notifications switch ignores OS permission |
| Help tiles and version | `auth/presentation/profile_help_section.dart` | Good | |
| Address book | `profile/presentation/address_book_screen.dart` | Minor | No unit prompt; keyboard closes each field |
| Push reason dialog | `core/notifications/push_permission_prompt.dart` | Minor | "Not now" is permanent |
| Account deletion | `profile_screen.dart`, `delete-account` | Minor | No warning with an order in progress |

### Admin — operations

| Page | File | Verdict | Reason |
|---|---|---|---|
| Shell / More | `admin/admin_shell.dart` | Good | |
| Home | `admin/dashboard/admin_dashboard_screen.dart` | **Needs work** | Stripe count misleading; two money cards overlap; Recent rows inert |
| Low Stock | `admin/dashboard/admin_low_stock_screen.dart` | Good | |
| Top Products | `admin/dashboard/admin_top_products_screen.dart` | Minor | Rows not tappable |
| Orders › All | `admin/orders/admin_orders_screen.dart` | **Needs work** | Status nouns as action labels; no customer name; search scoped by chip |
| Order detail (staff) | `order_detail_screen.dart`, `order_payment_section.dart` | **Needs work** | No next action for staff |
| Orders › Fulfillment | `admin/delivery/admin_delivery_screen.dart` | Minor | "Get courier rates" silent with no date |
| Parcel panel | `admin/delivery/parcel_fulfillment_panel.dart` | Good | |
| Pickup diagnostics | `admin/delivery/pickup_diagnostics_panel.dart` | Good | |
| Customer profile | `admin/customers/admin_customer_profile_screen.dart` | Minor | Phone/email plain text |
| Analytics | `admin/analytics/admin_analytics_screen.dart` | Minor | Visits only, yet revenue cards lead here |
| Notifications (staff) | `notifications_screen.dart` | **Needs work** | Shop-wide ops alerts do nothing on tap |
| Invoice | `orders/utils/invoice_pdf.dart` | Minor | Always "TAX INVOICE"; totals rows do not add up visually |
| Packing label | `orders/utils/packing_slip_pdf.dart` | Minor | Wrong copy for hand-delivered fish |

### Admin — catalogue and content

| Page | File | Verdict | Reason |
|---|---|---|---|
| Products list | `admin/products/admin_products_screen.dart` | Minor | Sold toggle still a 28 pt target |
| Product editor | `admin/products/admin_product_edit_screen.dart` | **Needs work** | Two silent wrong-stock bugs; sale locked on variant products; no Gender |
| Home Banners | `admin/banners/admin_banners_screen.dart` | Minor | Failed save can look like a dead button |
| Knowledge | `admin/knowledge/*.dart` | **Needs work** | Unguarded actions; "Publish" does not publish a hidden guide |
| Services | `admin/services/admin_services_screen.dart` | Minor | Guard misses typed text |
| Promo codes | `admin/promo/admin_promo_screen.dart` | **Needs work** | Delete unguarded and erases redemption history |
| Reviews | `admin/reviews/admin_reviews_screen.dart` | Good | |
| Settings | `admin/settings/admin_settings_screen.dart` | **Needs work** | Cannot save once the postcode is filled in |

## P0 — wrong information, blocked task or data loss

Checked in code by the lead unless marked.

1. **Admin Settings cannot be saved once the sender postcode is filled in.** `admin_settings_screen.dart:210` uses `RegExp(r'^\d{6}\$')`; in a raw string `\$` is a literal dollar, so `738343` fails (confirmed by running it in Dart). GST, phone, delivery days and everything else on the page are blocked. In since ba5c797 (14 Nov), first shipped in 1.0.28. Fix: `r'^\d{6}$'`, digits-only formatter, a save test with a postcode.
2. **Customer is trapped on the order page after a slow payment confirmation.** `checkout_screen.dart:450` does `context.go('/orders/$id')` without `justPlaced`; the page then has no back arrow (nothing to pop) and no "Continue Shopping" (`order_detail_screen.dart:103`, `:783`). On iOS the only exit is quitting the app. Introduced by the Sprint 1 confirming state; in 1.0.28. Fix: close button to Shop when `!context.canPop()`, and show Continue Shopping while confirming.
3. **"Duplicate option" shifts weight × size stock down a row.** `admin_product_edit_screen.dart:327-337` inserts a row without re-keying the index-keyed matrix cells; every weight below shows and saves the stock of the one above. Fix: re-key on insert or key by a stable row id.
4. **Renaming a size label zeroes that size's stock** (same file `:1167-1171`, `:393-398`, `:463`; reviewer-verified). Cells are keyed by label text; the old label's rows are deleted on save. Fix: key cells by row identity.
5. **A product with weight options cannot be put on sale, and its "Show price" switch is locked.** The whole price block is under `IgnorePointer` when variants exist (`:960-963`). All 20 production products have variants. Smallest fix: move the switch out and say sale is not available for products with options; a per-option sale price needs a schema column.
6. **Terms promise a cancellation the app does not offer.** `terms_screen.dart:58-59` says orders may be cancelled before packing from the order page; the app only cancels unpaid orders and otherwise sends a request for shop review. Section 10 points at a "Contact us" option that does not exist. Fix: rewrite section 6 and 10; add a live-fish clause before the first fish is listed.
7. **"N Stripe transactions" on Home counts unpaid and cancelled checkouts.** `0078_sprint3_hardening.sql:227-239` counts every order with a PaymentIntent. The amount is right, the count is not. Fix: count only orders that contribute to the sum; caption "After refunds · 5 paid orders". Needs a small migration.

## P1 — conversion, ops time, clarity, accessibility

Customer
- **Back is allowed while payment is processing** (`checkout_screen.dart`, no `PopScope`): the customer can pay, leave, and land on a full cart, and could pay again. Fix: `PopScope(canPop: !_processing)` and "Confirming payment… please keep this screen open"; persist the awaiting-confirmation record.
- **After 60 s the confirming state turns back into "Complete payment / Cancel Order"** for a paid order (`order_detail_screen.dart:280-296`). Fix: a third state, "We're still confirming your payment. You have not been charged twice — please don't pay again.", with Contact support.
- **Sign-up with an existing email shows "Confirm your email — we sent a link"** and no mail arrives (`auth_repository.dart:157`). Fix: treat empty `identities` as existing: "An account with this email already exists. Log in, or use Forgot password."
- **GST and delivery told three different ways.** Cart footer "Delivery and GST are added at checkout" is hard-coded and untrue with inclusive GST or a fish in the cart; checkout lists inclusive GST among the rows that sum; order detail shows no GST line although the snapshot exists.
- **Product page has no route to the cart** (app bar has only Share and heart). The button-free card makes this the only place to add to cart. Fix: cart badge button in the app bar; snackbar 4 s.
- **Product page loading and error states have no way back** (`product_detail_screen.dart:906-910`).
- **Koi and Arowana chips show "No matching products"** while production has no fish. Fix: "No koi available right now" with "Ask the farm".
- **Review row overflows at 360 dp** (`reviews_section.dart:453-489`, probe: 12 px at 1.0×) and **growth-stage cards clip text** (`knowledge_screen.dart:262`, probe: 16 px at 1.0×).
- **Profile says push alerts are on when the OS permission was never granted**; "Not now" on the reason dialog can never be undone in the app.
- **Auth screens can show raw Supabase exception text** (`login_screen.dart:531-534`) and developer copy about `.env`.
- **Account can be deleted with a paid order in progress, no warning.**
- **Form errors not announced** on login, sign-up, forgot, reset, address (no live region); two review controls under 48 dp.

Admin
- **Order detail is a dead end for staff**, and pushes, stuck rows and the new ops alerts all land there; shop-wide ops alerts do nothing on tap. Fix: a staff action bar (Start packing / Manage delivery / Mark as delivered, overflow Refund… / Cancel…); route `ops-daily:easyparcel_disconnected` to Settings.
- **Home money cards are indistinguishable**: "Total Revenue" and "Collected through Stripe" are the same number for a Stripe-only shop, formatted differently, and both open Analytics, which has no money. Fix: one "Sales after refunds" card.
- **Cancellation dialog**: dismiss button "Keep order" reads as a decision; neither refund confirmation states the amount. Fix: "Back"; "Refund S$84.50".
- **Orders › All uses status nouns as actions** ("Packing", "Refunded", "Cancelled"), giving "Cancel this order? [Cancel] [Cancelled]".
- **"Get courier rates" does nothing when no pickup date is chosen** (`admin_delivery_screen.dart:828`).
- **Search is silently scoped by the status chip; order cards never show the customer name.**
- **Home "Recent Orders" rows are inert and show the raw enum.**
- **A courier order cannot be marked delivered by hand** if the carrier never reports it.
- **Unsaved-changes guard misses typed text** on guide, variety, service, promo and settings forms (only the product editor and banner form rebuild on typing).
- **Guide hide/delete and promo delete are unguarded**; deleting a used promo cascades away its redemption history. Fix: `GuardedWrite`; "Turn off" instead of delete for a used code.
- **Banner form: a failed validation or save can be off-screen.**
- **A live fish's gender cannot be entered** (no field; the card is designed around "45 cm · Male").
- **Save is the last item of a very long product editor**; changing one stock number means crossing it twice. Fix: pinned Save.
- **Removing a support contact is instant and public** (no confirm).
- **Invoice always "TAX INVOICE" with a GST row**, no GST registration number; totals rows do not add up visually. Depends on the shop's GST registration (not checked).

## P2 — polish

- Dates in US order on reviews and notifications ("Nov 14, 2026") vs "24 Nov" elsewhere.
- Banner auto-advance continues under VoiceOver/TalkBack; dots 44 dp.
- Deleting your own review can fail silently; signed-in reviewers see their review twice.
- Selected option keeps old price and stock after pull-to-refresh.
- "Recommended for you" cards lack rating/sold; heading is not `SectionLabel`.
- Every category chip tap refetches a 20-product catalogue.
- Reset password has no exit; address form has no unit prompt, no "next" key, no discard guard.
- Staff see customer-voiced copy ("Refund failed — contact shop"); packing label wrong for hand delivery; "Packing slip" vs "Packing label".
- Home offline shows "—" with no retry; stuck rows read "created 4320 min ago"; every admin alert has the truck icon.
- Sold toggle 28 pt; "kg" label; matrix cells unlabelled; "Show prices by default" switch does nothing; delivery-days helper says "shop cards".
- Banner schedule: cancelling the time picker still sets the date at 00:00.
- Knowledge: "Publish" on an edit, blank empty lists, raw Markdown in the row subtitle.
- Copy batch: "Customer reason:", "Returned:", "Orders that are to pay…", "Calculating SGD delivery cost…", "Waiting for totals".
- Dead code: `order_success_screen.dart`.

## Well done — keep as is

- Payment truthfulness in checkout: one idempotency key, server amount compared before the sheet, sheet success never shown as paid.
- Cancellation and refund wording never promises money that has not moved.
- Fulfillment booking safety: actions locked while one is in flight, saved truth re-read after a failure.
- Product card geometry has one source (`ProductCard.bodyHeight`); one merged semantics label.
- Hero carousel fails soft: no space when empty, last good slides kept, static under Reduce Motion.
- Photo strip and upload path in the product editor; banner "Link to" picker; `GuardedWrite`.

## Defer / cut

Back-in-stock alerts, heart on the card, promo start date and minimum spend, revenue charts, customer list screen, Chinese localisation, in-app video upload, Home health line from `admin_ops_health()` (until alert taps work).

## Suggested order

1. P0 1, 2 and 6 plus "back while paying" — small, in 1.0.28 today, worth a 1.0.29 before more testers update.
2. P0 3, 4, 5 and the Stripe count — stock integrity and the editor.
3. Customer P1 (cart entry on the product page, sign-up, GST wording, empty Koi/Arowana).
4. Admin P1 (staff action bar on order detail, Orders labels, Home money card).
5. P2 batch.
