-- Marugen Koi Farm — 0015: promo code usage limits.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)
--
-- Before this, a promo code was reusable an unlimited number of times by
-- anyone until an admin manually deactivated it — no total cap, no
-- per-customer limit. This adds both:
--   1. An optional overall cap (`max_redemptions`, null = unlimited),
--      enforced atomically so concurrent checkouts can't both slip past it.
--   2. A hard one-redemption-per-user-per-code rule, enforced by a unique
--      constraint on `promo_code_redemptions` so a race between two
--      requests from the same user can't double-redeem either.
-- Both are applied/rolled-back from create-payment-intent (application
-- code) and released automatically if the order is later cancelled (the
-- same trigger pattern as stock release in 0009/0010).

alter table public.promo_codes
  add column if not exists max_redemptions int,
  add column if not exists times_redeemed int not null default 0;

comment on column public.promo_codes.max_redemptions is
  'Total number of orders that may use this code. Null = unlimited.';
comment on column public.promo_codes.times_redeemed is
  'Incremented atomically by create-payment-intent, decremented if the redeeming order is cancelled before payment.';

create table if not exists public.promo_code_redemptions (
  id uuid primary key default gen_random_uuid(),
  promo_code_id uuid not null references public.promo_codes (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  order_id uuid not null references public.orders (id) on delete cascade,
  created_at timestamptz not null default now(),
  -- One redemption per user per code, ever — this is what actually makes
  -- "one use per customer" race-safe: two concurrent checkout attempts by
  -- the same user racing past the earlier application-level check will
  -- still only let one INSERT succeed here.
  unique (promo_code_id, user_id)
);

alter table public.promo_code_redemptions enable row level security;

-- No public policies: only the service-role key (edge functions) reads/
-- writes this table directly. Admins can view it for reporting.
create policy "Admins can view promo redemptions" on public.promo_code_redemptions
  for select using (public.is_admin());

-- ---------------------------------------------------------------------
-- Atomic "claim a redemption slot" — supabase-js can't express
-- `times_redeemed = times_redeemed + 1 WHERE times_redeemed < max_redemptions`
-- as a single client-side .update() call, so this RPC does the
-- check-and-increment as one statement server-side. Returns true iff a
-- slot was claimed (row updated); false means the cap was already hit.
-- Called from create-payment-intent right before creating the Stripe
-- PaymentIntent, mirroring the atomic stock claim in
-- apply_order_item_stock (0010_payment_integrity.sql).
-- ---------------------------------------------------------------------
create or replace function public.claim_promo_redemption(p_promo_id uuid)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  v_updated int;
begin
  update public.promo_codes
     set times_redeemed = times_redeemed + 1
   where id = p_promo_id
     and (max_redemptions is null or times_redeemed < max_redemptions);
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

grant execute on function public.claim_promo_redemption(uuid) to service_role;

-- Symmetric release for when the redemption INSERT itself fails (e.g. the
-- user already redeemed this code — unique-constraint violation) after a
-- slot was already claimed above; keeps times_redeemed accurate rather
-- than leaking a phantom redemption for an order that never got created.
create or replace function public.release_promo_redemption(p_promo_id uuid)
returns void
language sql
security definer set search_path = public
as $$
  update public.promo_codes
     set times_redeemed = greatest(0, times_redeemed - 1)
   where id = p_promo_id;
$$;

grant execute on function public.release_promo_redemption(uuid) to service_role;

-- ---------------------------------------------------------------------
-- Release a redemption if its order is cancelled before it was ever paid
-- (mirrors restore_stock_on_cancel in 0009/0010 — same trigger, same
-- transition guard, so a stale pending order swept up by
-- cancel_stale_pending_orders (0014) also frees the promo code, not just
-- the stock).
-- ---------------------------------------------------------------------
create or replace function public.restore_promo_on_cancel()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.status = 'cancelled'
     and old.status in ('pending', 'paid', 'packing', 'shipped')
     and new.promo_code is not null then
    -- Deleting the redemption row is what lets this user apply the same
    -- code again later; decrementing times_redeemed is what frees a slot
    -- under the overall cap.
    delete from public.promo_code_redemptions where order_id = new.id;

    update public.promo_codes
       set times_redeemed = greatest(0, times_redeemed - 1)
     where code = new.promo_code;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_restore_promo_on_cancel on public.orders;
create trigger orders_restore_promo_on_cancel
  after update of status on public.orders
  for each row execute function public.restore_promo_on_cancel();
