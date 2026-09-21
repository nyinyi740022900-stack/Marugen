-- Marugen Koi Farm — 0041: idempotency key for create-payment-intent.
-- Run with: supabase db push
--
-- A client retry after a network hiccup (the checkout request actually
-- succeeded server-side — order created, stock reserved, PaymentIntent
-- created — but the response never reached the client, e.g. a timeout)
-- previously created a *second* pending order + PaymentIntent + stock
-- reservation for what the customer thinks is the same "Pay" tap.
-- create-payment-intent now accepts a client-generated idempotency_key
-- (stable per checkout screen instance — see checkout_screen.dart) and
-- looks up an existing pending order with that key before creating a new
-- one, returning the same order/PaymentIntent instead of a duplicate.
--
-- The unique index is partial (`where status = 'pending'`) so the key
-- naturally becomes reusable once that order resolves (paid/cancelled) —
-- there's no reason to block a customer's *next*, unrelated checkout
-- attempt just because it happens to reuse a key from an order that
-- already finished.

alter table public.orders add column if not exists idempotency_key text;

create unique index if not exists orders_user_pending_idempotency_key_uidx
  on public.orders (user_id, idempotency_key)
  where idempotency_key is not null and status = 'pending';
