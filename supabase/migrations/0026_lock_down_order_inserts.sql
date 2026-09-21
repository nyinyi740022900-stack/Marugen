-- Closes a critical RLS gap: the original insert policies on `orders` and
-- `order_items` (0001_init.sql) only checked `auth.uid() = user_id`, with no
-- constraint on `status`, `stripe_payment_intent_id`, or price columns. A
-- client could insert an order directly with status='paid' and arbitrary
-- prices, skipping create-payment-intent/stripe-webhook entirely — the
-- apply_order_item_stock trigger (0010_payment_integrity.sql) would then
-- still decrement/mark-sold real stock for an order nobody paid for.
--
-- Order creation in this app only ever happens server-side, inside
-- create-payment-intent (using the service-role key, which bypasses RLS
-- anyway) — see supabase/functions/create-payment-intent/index.ts. The
-- client (lib/features/orders/data/order_repository.dart) only reads,
-- updates its own status to 'cancelled' (0007_customer_order_cancel.sql),
-- or lets an admin update status. So tightening client inserts to
-- pending-only, unpaid-only rows does not break any real flow — it just
-- removes an insert path that should never have been usable by a client
-- in the first place.

drop policy if exists "Users can create their own orders" on public.orders;
create policy "Users can create their own pending orders"
  on public.orders for insert
  with check (
    auth.uid() = user_id
    and status = 'pending'
    and stripe_payment_intent_id is null
  );

drop policy if exists "Users can insert items into their own orders" on public.order_items;
create policy "Users can insert items into their own pending orders"
  on public.order_items for insert
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and o.user_id = auth.uid()
        and o.status = 'pending'
    )
  );
