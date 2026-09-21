-- Marugen Koi Farm — 0014: auto-release stock from abandoned checkouts.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)
--
-- Problem: create-payment-intent reserves stock (marks a live fish
-- is_sold, decrements variant/product stock_quantity) the moment an
-- `orders` row + its `order_items` are inserted — *before* the customer
-- actually pays (see 0010_payment_integrity.sql). That reservation is
-- only released when the order transitions to `cancelled`, which today
-- only happens if:
--   (a) the client explicitly dismisses the Stripe payment sheet and
--       calls cancelMyOrder(), or
--   (b) Stripe sends `payment_intent.payment_failed`/`canceled`.
-- Neither fires if the app crashes, is force-quit, loses network mid
-- checkout, or the customer simply never returns — Stripe PaymentIntents
-- do not expire on their own. A single interrupted checkout could
-- therefore lock a unique live fish as "Sold" forever with no automatic
-- recovery.
--
-- Fix: a scheduled job that cancels any `orders` row still `pending`
-- well past a normal checkout window. Cancelling routes through the
-- existing `orders_restore_stock_on_cancel` trigger (0009/0010), so stock
-- and `is_sold` are released the same way a customer-initiated cancel
-- releases them — no new release logic needed here.
--
-- 30 minutes is generous for a card/PayNow/3DS confirmation to complete;
-- if a genuine payment somehow resolves after that window, the
-- `stripe-webhook`'s `.eq('status', 'pending')` guard will simply no-op
-- (the order is already `cancelled`) rather than corrupt state — the
-- edge case is a false cancellation of a very slow real payment, which
-- is safer than a real fish being stuck unsold indefinitely.

create or replace function public.cancel_stale_pending_orders()
returns void
language sql
security definer
set search_path = public
as $$
  update public.orders
     set status = 'cancelled'
   where status = 'pending'
     and created_at < now() - interval '30 minutes';
$$;

-- Requires the pg_cron extension, available on all Supabase projects
-- (Database → Extensions → pg_cron, or this CREATE EXTENSION call).
create extension if not exists pg_cron with schema extensions;

-- Re-scheduling is idempotent: unschedule first so re-running this
-- migration (or pushing it twice) doesn't create duplicate jobs.
select cron.unschedule(jobid)
  from cron.job
 where jobname = 'cancel-stale-pending-orders';

select cron.schedule(
  'cancel-stale-pending-orders',
  '*/10 * * * *', -- every 10 minutes
  $$select public.cancel_stale_pending_orders();$$
);
