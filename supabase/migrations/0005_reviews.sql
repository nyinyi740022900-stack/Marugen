-- Marugen Koi Farm — product reviews & ratings.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)

create table public.product_reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (product_id, user_id)
);

alter table public.product_reviews enable row level security;

create policy "Anyone can view reviews" on public.product_reviews for select using (true);
create policy "Users manage their own reviews" on public.product_reviews for insert with check (auth.uid() = user_id);
create policy "Users can update their own reviews" on public.product_reviews for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users can delete their own reviews" on public.product_reviews for delete using (auth.uid() = user_id);
