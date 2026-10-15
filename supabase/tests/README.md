Run the stock/review and payment cancellation boundary regressions with local PostgreSQL (`initdb`, `pg_ctl`, `psql`, and Python 3 on PATH):

```sh
supabase/tests/run_stock_review_boundaries.sh
```

The runner creates and removes a temporary database cluster with a private Unix socket and no TCP listener. It never loads app credentials or connects to a deployed database. `--baseline` skips migration 0052 and should fail, reproducing the original stock/review gaps. `--payment-baseline` applies 0052 but skips 0053 and should fail on the original direct cancellation gap.

The bootstrap supplies minimal local Supabase auth/storage primitives and runs the actual relevant migrations. The tests exercise customer, admin and service database roles against real RLS policies and triggers. They cover order insertion authorization, quantity/product/variant/size validation, atomic stock reservation and cancellation restoration, review moderation/reply protection, and legitimate author edits. A separate migration check preserves a historical negative quantity while rejecting new invalid writes through a `NOT VALID` constraint.

This focused harness does not simulate PostgREST JWT verification, load unrelated migrations/extensions, or replace a full Supabase migration reset. `stock_review_boundaries.sql` can also run against a disposable Supabase test database after migration 0052; its fixtures are rolled back.

The payment cancellation integration checks apply migration 0053 and exercise customer/admin rejection, verified service cancellation, paid/packing cancellation rejection, refund transitions, and stale orphan cleanup without releasing linked payment stock. They call the actual cleanup function locally; they do not execute cron scheduling or contact Stripe.

The payment tests also reject clearing or replacing an established PaymentIntent, including two-step admin cancellation attempts, while allowing the backend to link a newly created order. Migration 0054 is checked against paid/refunded retry keys and verified cancelled-key reuse. `--idempotency-baseline` skips 0054 and reproduces the paid retry gap. A committed duplicate historical fixture verifies migration rejection preserves both orders and the previous unique index before cleanup and a successful migration attempt.

The concurrent reservation/cancellation test uses two real database sessions in both orderings. It observes the second operation waiting on a row lock, then verifies exact stock restoration when insertion wins and rejects late insertion when cancellation wins. New order items require a pending parent; verified review fixtures reserve stock before moving their parent order to paid.

Migration 0055 adds the financial-authority regression: authenticated admin roles cannot forge payment/refund transitions or checkout identity/amount/refund metadata, while service backend transitions and legitimate admin fulfillment remain possible.

The opt-in `local_payment_acceptance.py`, `local_admin_acceptance.py` and `local_network_acceptance.py` scripts require `LOCAL_SUPABASE_STATUS` pointing to a private local Supabase status JSON. They enforce a loopback backend; payment/network tests additionally require Stripe **test** credentials and local webhook configuration. They are not production smoke tests. Use a disposable local stack and synthetic accounts only; never commit status/credential fixtures. Exact executed scope and evidence are in `docs/audit-fixes-verification-2026-10-15.md`.
