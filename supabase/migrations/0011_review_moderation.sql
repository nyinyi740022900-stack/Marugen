-- Marugen Koi Farm — 0011: review moderation (hide abusive reviews)
-- Run with: supabase db push   (or paste into the Supabase SQL editor)

alter table public.product_reviews
  add column if not exists is_hidden boolean not null default false;

-- Public sees only visible reviews; authors still see their own; admins see all.
drop policy if exists "Anyone can view reviews" on public.product_reviews;
create policy "Visible reviews are public"
  on public.product_reviews for select
  using (
    is_hidden = false
    or auth.uid() = user_id
    or public.is_admin()
  );

-- Admins can hide/unhide (and otherwise update) any review.
drop policy if exists "Admins can moderate reviews" on public.product_reviews;
create policy "Admins can moderate reviews"
  on public.product_reviews for update
  using (public.is_admin())
  with check (public.is_admin());
