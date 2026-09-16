-- Marugen Koi Farm — customer wishlist / favorites.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)

create table if not exists public.wishlist_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, product_id)
);

alter table public.wishlist_items enable row level security;

create policy "Users manage their own wishlist" on public.wishlist_items for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
