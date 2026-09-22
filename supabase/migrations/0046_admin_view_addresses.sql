-- Same gap 0045 fixed for profiles: public.addresses only ever had a
-- self-only policy (auth.uid() = user_id, for all), so an admin querying
-- a customer's saved addresses (e.g. for a "view customer" screen) got
-- nothing back under RLS. Read-only — admins can see a customer's
-- addresses but not edit/delete them, same restriction as the existing
-- admin policies on orders/order_items.
create policy "Admins can view all addresses"
  on public.addresses for select
  using (public.is_admin());
