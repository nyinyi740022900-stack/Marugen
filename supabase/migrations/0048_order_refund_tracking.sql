-- Marugen Koi Farm — 0048: refund tracking columns.
--
-- Admin's "Mark as refunded" action (admin_orders_screen.dart) previously
-- just flipped orders.status to 'refunded' with no actual money movement —
-- the customer's card was never refunded, only relabeled. This adds the
-- columns the new `stripe-refund` Edge Function needs to record a real
-- Stripe refund (id/amount/when), so "refunded" in this app always means
-- money was actually returned via Stripe, not just a status label.

alter table public.orders
  add column if not exists stripe_refund_id text,
  add column if not exists refund_amount numeric,
  add column if not exists refunded_at timestamptz;

comment on column public.orders.stripe_refund_id is
  'Stripe Refund object id — set by the stripe-refund Edge Function once a real refund is issued.';
comment on column public.orders.refund_amount is
  'Amount actually refunded via Stripe (same currency/unit as orders.total).';
comment on column public.orders.refunded_at is
  'When the Stripe refund was issued — distinct from status change time if ever backfilled.';
