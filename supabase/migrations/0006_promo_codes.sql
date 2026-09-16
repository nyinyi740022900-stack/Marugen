-- Marugen Koi Farm — promo/discount codes at checkout.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)

create table public.promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('percent', 'fixed')),
  discount_value numeric(10,2) not null,
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.promo_codes enable row level security;

create policy "Anyone can check an active promo code" on public.promo_codes for select using (active = true);
create policy "Admins can manage promo codes" on public.promo_codes for all
  using (public.is_admin()) with check (public.is_admin());

-- Persist the applied promo code + discount onto the order so it shows on
-- the order detail screen / receipt.
alter table public.orders add column if not exists promo_code text;
alter table public.orders add column if not exists discount_amount numeric(10,2);
