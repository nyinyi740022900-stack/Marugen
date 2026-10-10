# Marugen customer UX: delivered fixes and 40/40 acceptance

Date: 2026-10-02. Scope: customer shopping, wishlist, cart, authentication continuation, checkout, and shared customer recovery. This is a source and bounded preview review, not a certification of every admin screen or production integration.

Updated: 2026-10-03. Dark mode is now implemented; the remaining integration and accessibility gates below still apply.

## Delivered

- Buy Now carries the exact selection into an isolated checkout. Guest login/signup preserves a validated local continuation. Account switches discard stale purchase intent instead of borrowing another account's cart.
- Payment requires a valid address, loaded settings/totals, completed promo validation, and no active payment. The persistent SafeArea action displays the amount. Account changes stop checkout continuation, including after native sheet initialization.
- Cart/checkout removal supports Undo with account and route guards. Checkout clears old cart snackbars. Late stock refreshes, hydration, and persistence cannot resurrect removed items or transfer another account's cart.
- Catalog actions have named 48-pixel targets and favorite state semantics. Two-line names, adaptive grids, readable secondary text, scalable categories, and reduced-motion behavior improve accessibility. Phone navigation retains labels; tablets/windows at 700 pixels use a labeled rail.
- Search no-results offers Clear filters. Select Options moves to the relevant selectors. Weight/size guidance uses known selection context without inventing fish or food properties.
- Wishlist updates roll back only the failed item, preserve other successful changes, and retry failed IDs loading before removal. Shared customer errors expose friendly Retry actions rather than internal exception details. Failed contact launches give guidance.
- Small-window error states scroll. Cart quantity controls remain usable. Checkout totals stack on narrow layouts or enlarged text instead of overflowing.
- Light / Dark / System appearance is available in both guest/signed-in Profile and Admin Settings. The preference is saved on the device. System follows device brightness; late settings loading cannot replace a newer user choice. Customer/admin/shared surfaces, text, borders, status colors, forms, dialogs, navigation and loading states resolve from the nearest theme. Stripe sheet style follows checkout brightness. Brand artwork, photos, media overlays and printed invoices keep their intended colors.

## Verification evidence

- Full Flutter test suite: **49 passed**. Includes the previous purchase/recovery/layout regressions plus saved appearance restoration, stale-load protection, system changes versus explicit choice, picker interaction, dark text/status contrast, dark checkout and navigation, and shared loading/empty states.
- Flutter analyzer: no errors or warnings; two existing informational deprecations remain in `admin_delivery_screen.dart` (`groupValue` and `onChanged`). Analyzer exits nonzero for these infos; it is not a clean-zero analyzer result.
- Independent scoped implementation review: PASS, with earlier purchase/Undo, reduced-motion, and wishlist-retry findings resolved.
- Independent dark-mode spec and quality review: PASS. Phone/tablet Light and Dark shop previews were inspected using local sample data; native status-bar safe area contrast was corrected in the confirmation batch. Current appearance evidence is in `ux-evidence/phone-light.png`, `phone-dark.png`, `tablet-light.png`, and `tablet-dark.png`. These are sample-data previews, not real inventory or payment verification.
- The regular application entry point also builds successfully for the iOS simulator after the final fixes; this is compilation evidence, not a production backend or payment test.
- iOS simulator preview compiles using actual customer widgets and local sample data. Phone and tablet shop layouts received bounded visual inspection. The final tablet inspection caught a red selected icon on a red indicator; the source now explicitly uses a white selected icon, with a passing contrast regression. `ux-evidence/iphone-shop.png` records the compact phone layout; `ux-evidence/ipad-shop-before-indicator-fix.png` records the tablet layout before that final icon correction. These fixtures do not validate real product images, backend availability, native Stripe payment, or full navigation integration.
- No live payment, production backend write, commit, or publication was performed.

## 40/40 evidence gates

The earlier 25/40 was a provisional review across ten heuristics, each worth four points. Completing source fixes does not establish ten perfect scores. Award 4/4 for a criterion only after its representative flows pass without a material unresolved finding; record the actual result, device, and evidence.

| Heuristic | Implemented evidence | Remaining acceptance evidence for 4/4 |
| --- | --- | --- |
| Visibility of system status | Loading/Retry states, promo/payment locks, persistent payment amount | Sandbox payment success, cancellation, decline, timeout, and order verification states on devices |
| Match with the real world | Clear amount/tax wording, contextual option guidance | Real SKU weights/sizes/delivery facts reviewed by shop owner and understood by novice shoppers |
| User control and freedom | Safe Undo, clear filters, account-bound purchase intent | Back/cancel through actual login, signup, native payment sheet, and failed checkout without losing intended work |
| Consistency and standards | Shared card/grid/recovery patterns, labeled adaptive navigation | Phone/tablet, Android/iOS, keyboard, and supported appearance modes audited with real content |
| Error prevention | Totals and promo gates; stale account and async race guards | Sandbox stock/price/address changes, repeated taps, network interruption, and idempotent order/payment behavior |
| Recognition rather than recall | Two-line names, option navigation, visible action amount | First-time users identify variants, delivery choices, and next steps without assistance |
| Flexibility and efficiency | Adaptive grids/rail, search reset, direct purchase flow | Returning users complete repeat shopping; keyboard and assistive navigation traverse actions in useful order |
| Aesthetic and minimalist design | Compact cards, readable secondary text, adaptive totals | Real images and long/discounted product data checked in both supported themes and large text |
| Recognize, diagnose and recover from errors | Friendly retry/contact/payment messages, item-level rollback | Offline/reconnect, expired session, declined payment, and lost verification response recover without duplicate purchase |
| Help and documentation | Selection guidance, FAQ/contact access, readable recovery | Shop-approved delivery, returns, care/feeding, and payment help answer observed user questions |

## Prioritized updates and acceptance work

1. **Release gate: integration and accessibility verification.** Use Stripe sandbox and test accounts to exercise payment failure/cancel/success and interrupted verification. Run VoiceOver/TalkBack, keyboard focus, Android enlarged text/display, and actual auth/back-navigation flows. Fix any reproduced issue before assigning scores.
2. **Resilience update.** Purchase intent is currently session memory; process restart deliberately yields an empty isolated checkout. If interrupted-purchase recovery is a product requirement, add an account-bound persisted draft with expiry, fresh price/stock validation, and a visible resume/discard choice. Never silently merge it into another user's cart.
3. **Appearance acceptance.** Dark mode implementation and representative automated/native preview checks are complete. Remaining acceptance covers real product imagery, Android/physical-device accessibility, and native Stripe sandbox presentation in both appearances. No live payment was used to validate this update.
4. **Content and usability validation.** Review real SKU guidance and shop policies with the owner. Observe first-time, returning, and assistive-technology shoppers completing find/select/save/remove/buy tasks. Record completion, mistakes, recovery, and unanswered questions, then resolve material findings and reassess each heuristic.

These updates are separate from the confirmed defects already fixed. The score remains unconfirmed until the evidence gates are completed; no new numerical score is invented here.
