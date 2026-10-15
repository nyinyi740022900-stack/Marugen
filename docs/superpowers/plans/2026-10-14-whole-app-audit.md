# Whole App Audit Plan

> **For agentic workers:** Execute this review task-by-task using executing-plans. This is an audit, not authorization to implement new product features. Preserve the existing uncommitted guest UI fixes.

**Goal:** Identify reproducible defects and release-verification gaps throughout the Marugen Android-first customer/admin app.

**Architecture:** Inventory every feature and route, inspect critical state/backend boundaries, run existing and focused diagnostic tests, and keep confirmed defects separate from checks that need a device or sandbox backend. Use the incumbent Flutter design and account/role model.

**Tech Stack:** Flutter, Riverpod, GoRouter, Supabase/PostgreSQL/Deno, Stripe, Firebase, EasyParcel.

**Spec:** Current user request to plan and check the whole app; `docs/ux-acceptance.md` records existing acceptance gates.

## Global Constraints

- English app copy; Burmese user-facing explanations.
- Android is the current release target; iPhone/iPad behavior remains a compatibility check.
- Read-only production services. No live charge, refund, shipment, account deletion, or admin data mutation.
- Do not change version, commit/push, deploy functions/migrations, or upload a beta during this audit.
- Never claim all files or all device behaviors passed when inspection/testing was partial.

### Task 1: Inventory and verification baseline

- [x] Enumerate feature screens, router destinations, backend functions, migrations, and tests.
- [x] Run baseline analysis/tests; record diagnostic warning and final analyzer verification limitation separately.
- [x] Check Android emulator/device availability and backend test runtime availability.

### Task 2: Account, access, and data isolation

- [ ] Trace guest → login/signup → original destination, sign-out, account switching, recovery and deletion.
- [ ] Check account-scoped providers and cached values across session changes.
- [ ] Inspect customer/admin routes, database RLS, and privileged function authentication.
- [x] Reproduce suspected data-isolation defects with isolated provider tests, without real customer data.

### Task 3: Purchase path and financial integrity

- [ ] Trace list/product → cart/Buy Now → address/promo/remarks → Stripe → confirmed order.
- [ ] Inspect server pricing, stock limits/reservation, idempotency, paid confirmation, webhook authorization, cancel/refund boundaries.
- [ ] Verify review purchase eligibility, unique review constraints and moderation.
- [ ] Mark Stripe sandbox, concurrent stock and interrupted-payment checks as pending if unavailable; source inspection alone is insufficient.

### Task 4: Whole-app interface and operations

- [ ] Screen-wide scan: loading/empty/error states, actionable recovery, icon labels, unsafe fixed sizes, keyboard insets, navigation and theme tokens.
- [ ] Inspect customer Orders, tracking, notifications, wishlist, addresses, knowledge, services, privacy/terms/help.
- [ ] Inspect admin Home, Products, Orders/Fulfillment/Payments, Knowledge, Promo, Reviews, Analytics, Settings and auxiliary customer/stock screens.
- [x] Reproduce material UI suspicions at 320-pixel width, 2× text, both appearances, and wider layouts when practical.
- [x] Separate static UI indicators from confirmed rendering or accessibility failures.

### Task 5: Evidence and release gates

- [x] Save confirmed findings with severity, trigger, file/line, evidence, and proposed regression/fix.
- [x] Save a sequential fix plan and the remaining Android/device/backend acceptance checklist.
- [ ] Report checked scope, passing checks, important defects, and unverified areas in Burmese.

## First-pass outcome

See `docs/whole-app-audit-2026-10-14.md`: five reproduced defects and two source permission risks. Unchecked steps remain explicit follow-up gates, not implied passes. No new app fixes or release mutations were made by this audit.
