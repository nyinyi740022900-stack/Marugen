-- Marugen Koi Farm — customer address book.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)

create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  label text not null default 'Home', -- e.g. Home, Office
  recipient_name text not null,
  phone text not null,
  line1 text not null,
  line2 text,
  city text not null default 'Singapore',
  postal_code text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.addresses enable row level security;

create policy "Users manage their own addresses" on public.addresses for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
