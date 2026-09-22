-- public.profiles has only ever allowed a user to select their own row
-- (auth.uid() = id) — no admin-wide policy was ever added, unlike every
-- other table in this schema. That's invisible on tables that denormalize
-- the customer's name onto the row itself (e.g. orders.shipping_address),
-- but review_repository.dart's admin query embeds the reviewer's profile
-- via a join (`select('*, profiles(full_name, avatar_url))`) — PostgREST
-- applies RLS to the joined table too, so that embed silently came back
-- null for every reviewer who wasn't the admin themselves, and the admin
-- Reviews screen fell back to "Customer" / a "?" avatar for everyone.
create policy "Admins can view all profiles"
  on public.profiles for select
  using (public.is_admin());
