# Marugen UX confidence implementation plan

> Execute in this session using subagent-driven development for scoped work and an independent final review. Preserve all pre-existing changes; do not commit or publish them.

**Goal:** Resolve every confirmed finding from the customer-flow review and document the remaining evidence required for an honest 40/40 assessment.

**Architecture:** Keep existing Riverpod providers, GoRouter navigation, Stripe payment processing and Marugen visual identity. Preserve purchase intent across authentication with a session-scoped provider; use reusable accessible controls and adaptive grid sizing rather than a replacement design.

**Tech stack:** Flutter, Riverpod, GoRouter, Supabase, Stripe.

**Spec:** User-approved findings and fixes in this chat (2026-10-02).

## Constraints and rulings

- Continue in the current dirty workspace: its current source is the audit target and contains valuable uncommitted work. Never revert another change.
- Purchase quantities, options, prices and backend validation remain authoritative; no live payment or production write during verification.
- Preserve brand, real product facts and account isolation. Guest intent must not expose another account's cart.
- Treat 40/40 as an evidence gate, not an automatic score after edits. Dark appearance requires comprehensive surface migration and is documented as a separate planned update, not falsely reported as delivered.
- Prefer meaningful regression/widget tests for purchase safety, loading gates, responsive layouts and accessible actions. Skip tests that only mirror copy changes.

## Task 1: Purchase and checkout safety

- [x] Add session-scoped purchase intent shared by card, detail and authentication flows; preserve explicit Buy Now selection and guest checkout snapshot without merging another account's cart.
- [x] Preserve safe local redirect through signup; clear or consume intent deliberately and prevent stale intent being used in later cart checkouts.
- [x] Require loaded totals and finished promo validation before payment; display amount beside persistent payment action with SafeArea.
- [x] Replace raw payment errors with actionable messages; prevent removal/changes during payment; support remove/Undo where safe.
- [x] Add meaningful regression tests and run tests/analyzer.

## Task 2: Discovery and accessible catalog

- [x] Unify card Buy Now with Task 1's intent interface. Expand card actions to 48 logical pixels with descriptive semantics and favorite selected state.
- [x] Distinguish search/category no matches from empty catalog; provide clear filters and clear-search label.
- [x] Share adaptive card grid delegate across shop, wishlist and skeletons; allow meaningful two-line names and increased text size.
- [x] Make Select Options action scroll to selectors; explain weight/size without inventing product properties; honor reduced motion for new transitions.
- [x] Fix wishlist optimistic rollback, remove target and recoverable errors.
- [x] Add bounded widget/layout/accessibility regression checks.

## Task 3: Shared recovery, navigation and cart

- [x] Use readable secondary text token while retaining appropriate contrasting labels on black app bars.
- [x] Replace raw customer errors with friendly Retry states and preserve form/user state.
- [x] Add account-safe cart Undo, readable cart names and adaptive/narrow cart layout; 48-pixel quantity controls.
- [x] Use rail navigation on wider customer windows; retain four labeled mobile destinations and tab state.
- [x] Ensure shared empty states scroll on small windows/large text.

## Verification and review

- [x] Run Flutter tests and analyzer using permitted SDK cache access; review only introduced warnings/errors.
- [x] Independent review of purchase isolation, auth redirects, totals gates, undo race conditions and large-text layout.
- [x] Attempt fresh device availability and bounded screenshot inspection if a runnable native target exists.
- [x] Write delivered/remaining checklist against all ten Nielsen heuristics and report actual evidence, without inflating scores.
