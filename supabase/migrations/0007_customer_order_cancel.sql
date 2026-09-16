-- Marugen Koi Farm — allow a customer to cancel their own pending/paid
-- order (before it enters packing). The existing "Admins can update
-- orders" policy only covers admins; customers had no update policy at
-- all, so this adds a narrowly-scoped one that ONLY allows flipping a
-- pending/paid order of their own to 'cancelled' — nothing else.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)

create policy "Users can cancel their own pending orders" on public.orders for update
  using (auth.uid() = user_id and status in ('pending', 'paid'))
  with check (auth.uid() = user_id and status = 'cancelled');
