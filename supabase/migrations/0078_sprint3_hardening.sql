-- Marugen Koi Farm — 0078: Sprint 3 backend hardening.
--
-- One self-contained file for the Supabase SQL editor. Safe to run again:
-- every statement is idempotent and the whole file is one transaction, so
-- a failure leaves the database exactly as it was.
--
-- APPLY THIS BEFORE deploying the Sprint 3 Edge Functions:
-- create-payment-intent writes the new GST columns on every checkout and
-- the EasyParcel token helper calls claim_easyparcel_token_refresh().
--
--   1. GST snapshot on orders (rate, included flag, amount in cents).
--   2. EasyParcel token refresh lease (one refresh at a time).
--   3. Indexes for the order, address, variant and promo lookups.
--   4. Admin aggregates: payments total and top products.
--
-- Rollback note (nothing here drops data):
--   1. re-run guard_server_owned_order_financials() from
--      0055_server_owned_order_financials.sql. The columns can stay (old
--      code ignores them) or:
--        alter table public.orders drop constraint orders_gst_snapshot_complete;
--        alter table public.orders drop column gst_percent,
--          drop column gst_included_in_price, drop column gst_amount_cents;
--      Dropping them loses the snapshots, and the Sprint 3
--      create-payment-intent must be rolled back first.
--   2. drop function public.claim_easyparcel_token_refresh(text);
--      alter table public.easyparcel_connection drop column refresh_started_at;
--      (roll back the Edge Functions that use easyparcel_token.ts first)
--   3. drop index if exists public.<name>;   -- per index below
--   4. drop function public.admin_payments_summary();
--      drop function public.admin_top_products(integer);

begin;

-- ---------------------------------------------------------------------
-- 1. GST snapshot.
--    create-payment-intent read settings.gst_percent at checkout but kept
--    only the total, and the invoice recomputed GST from the CURRENT
--    setting, so changing the rate rewrote every past invoice.
--
--    Names follow settings.gst_percent / gst_included_in_price and the
--    *_cents convention of the shipping columns (0058).
--    Orders created before this migration keep NULL in all three: they
--    are deliberately not backfilled with today's rate. The app falls
--    back to its old calculation when gst_percent is null.
--
--    gst_amount_cents is the GST on merchandise (after promo discount,
--    before shipping):
--      included in price  -> the GST portion inside the merchandise total
--      added on top       -> the GST added to it
-- ---------------------------------------------------------------------
alter table public.orders
  add column if not exists gst_percent numeric(5, 2),
  add column if not exists gst_included_in_price boolean,
  add column if not exists gst_amount_cents integer;

comment on column public.orders.gst_percent is
  'GST rate (percent) applied at checkout. NULL for orders placed before migration 0078.';
comment on column public.orders.gst_included_in_price is
  'Whether prices already included GST at checkout. NULL for orders placed before migration 0078.';
comment on column public.orders.gst_amount_cents is
  'GST on merchandise in SGD cents, computed once by create-payment-intent. NULL for orders placed before migration 0078.';

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.orders'::regclass
       and conname = 'orders_gst_snapshot_complete'
  ) then
    -- All three or none, and sane values. Existing rows are all NULL.
    alter table public.orders add constraint orders_gst_snapshot_complete check (
      (gst_percent is null and gst_included_in_price is null and gst_amount_cents is null)
      or (gst_percent is not null and gst_included_in_price is not null
          and gst_amount_cents is not null
          and gst_percent >= 0 and gst_percent <= 100
          and gst_amount_cents >= 0)
    );
  end if;
end;
$$;

-- Same function as 0055 (its only definition), plus the GST columns.
-- Customers have no INSERT or UPDATE policy on orders (0052, 0053); staff
-- have "Admins can update orders", which is what this trigger restrains.
-- New: a snapshot that has been written is immutable for every role, the
-- payment backend included, so no later job can restate a past invoice.
create or replace function public.guard_server_owned_order_financials()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (old.gst_percent is not null
      or old.gst_included_in_price is not null
      or old.gst_amount_cents is not null)
     and (new.gst_percent is distinct from old.gst_percent
          or new.gst_included_in_price is distinct from old.gst_included_in_price
          or new.gst_amount_cents is distinct from old.gst_amount_cents) then
    raise exception 'The GST snapshot of an order is immutable';
  end if;

  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  if new.status is distinct from old.status
     and new.status in ('paid', 'refunded') then
    raise exception 'Payment and refund status must be verified by the payment backend';
  end if;

  if new.total is distinct from old.total
     or new.user_id is distinct from old.user_id
     or new.idempotency_key is distinct from old.idempotency_key
     or new.promo_code is distinct from old.promo_code
     or new.discount_amount is distinct from old.discount_amount
     or new.stripe_refund_id is distinct from old.stripe_refund_id
     or new.refund_amount is distinct from old.refund_amount
     or new.refunded_at is distinct from old.refunded_at
     or new.gst_percent is distinct from old.gst_percent
     or new.gst_included_in_price is distinct from old.gst_included_in_price
     or new.gst_amount_cents is distinct from old.gst_amount_cents then
    raise exception 'Checkout financial records may only be changed by the payment backend';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_server_owned_financials on public.orders;
create trigger orders_server_owned_financials
  before update on public.orders
  for each row execute function public.guard_server_owned_order_financials();

-- ---------------------------------------------------------------------
-- 2. EasyParcel token refresh lease.
--    Two requests that both found the access token expired each sent the
--    same refresh token to EasyParcel; if the provider rotates refresh
--    tokens, the slower one stored a dead token and the shop had to
--    reconnect. The refresher now claims a short lease first, in one
--    UPDATE, and everyone else waits for its result.
--    The lease is bound to the refresh token it was read with, and
--    expires by itself after 60 seconds (the refresh call times out
--    after 15) so a crashed function cannot block refreshing for good.
-- ---------------------------------------------------------------------
alter table public.easyparcel_connection
  add column if not exists refresh_started_at timestamptz;

create or replace function public.claim_easyparcel_token_refresh(p_refresh_token text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_claimed int;
begin
  update public.easyparcel_connection
     set refresh_started_at = now()
   where id = 1
     and refresh_token = p_refresh_token
     and (refresh_started_at is null
          or refresh_started_at < now() - interval '60 seconds');
  get diagnostics v_claimed = row_count;
  return v_claimed = 1;
end;
$$;

-- Server only: the Edge Functions call it with the service-role key.
revoke all on function public.claim_easyparcel_token_refresh(text)
  from public, anon, authenticated;
grant execute on function public.claim_easyparcel_token_refresh(text) to service_role;

-- ---------------------------------------------------------------------
-- 3. Indexes.
--    None of these columns had an index: the only indexes on these
--    tables were primary keys, orders(stripe_payment_intent_id),
--    the partial orders(user_id, idempotency_key) and
--    promo_code_redemptions(promo_code_id, user_id).
--    Plain CREATE INDEX (not CONCURRENTLY, which cannot run inside a
--    transaction): the tables are small, the lock is brief.
-- ---------------------------------------------------------------------
create index if not exists order_items_order_id_idx
  on public.order_items (order_id);
create index if not exists order_items_product_id_idx
  on public.order_items (product_id);
create index if not exists orders_user_id_created_at_idx
  on public.orders (user_id, created_at desc);
create index if not exists orders_status_created_at_idx
  on public.orders (status, created_at desc);
create index if not exists orders_qxpress_tracking_no_idx
  on public.orders (qxpress_tracking_no);
create index if not exists orders_easyparcel_shipment_id_idx
  on public.orders (easyparcel_shipment_id);
create index if not exists addresses_user_id_idx
  on public.addresses (user_id);
create index if not exists product_variants_product_id_idx
  on public.product_variants (product_id);
create index if not exists promo_code_redemptions_order_id_idx
  on public.promo_code_redemptions (order_id);

-- ---------------------------------------------------------------------
-- 4. Admin aggregates (same pattern as admin_order_summary in 0074).
--    The Payments pane and Top Products added up an unbounded all-orders
--    fetch in the app; PostgREST returns at most 1000 rows, so both
--    silently stopped growing. The rules below are the app's own.
-- ---------------------------------------------------------------------

-- Payments pane "Collected after refunds" (Order.netPaidAmount summed
-- over orders that have a Stripe PaymentIntent):
--   paid / packing / shipped / delivered  -> total - refund_amount
--   refunded but the refund is not confirmed succeeded -> total - refund_amount
--   anything else (pending, cancelled, fully refunded)  -> 0
-- each clamped to [0, total]. No date range: all time.
-- Not the same number as admin_order_summary().total_revenue, which also
-- counts orders without a PaymentIntent.
create or replace function public.admin_payments_summary()
returns table (transaction_count bigint, collected numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  return query
  select count(*),
         coalesce(sum(
           case
             when o.status in ('paid', 'packing', 'shipped', 'delivered')
               or (o.status = 'refunded'
                   and o.refund_status is not null
                   and o.refund_status <> 'succeeded')
             then least(greatest(o.total - coalesce(o.refund_amount, 0), 0), o.total)
             else 0
           end
         ), 0)
    from public.orders o
   where nullif(o.stripe_payment_intent_id, '') is not null;
end;
$$;

-- Top Products (rankTopProducts in admin_dashboard_screen.dart): units
-- per product NAME over every order that is not cancelled (pending and
-- refunded orders count, as they do in the app today), most units first.
-- No date range: all time.
--   product_id  the product of the newest line with that name; null once
--               the product has been deleted
--   revenue     quantity x unit_price of those lines, before any order
--               level promo discount, shipping or refund
-- Ties are broken by name so the order is stable. At most 1000 rows.
create or replace function public.admin_top_products(p_limit int default 100)
returns table (product_name text, product_id uuid, units bigint, revenue numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  return query
  select i.product_name,
         (array_agg(i.product_id order by o.created_at desc, i.id)
            filter (where i.product_id is not null))[1],
         sum(i.quantity)::bigint,
         coalesce(sum(i.quantity * i.unit_price), 0)
    from public.order_items i
    join public.orders o on o.id = i.order_id
   where o.status <> 'cancelled'
   group by i.product_name
   order by sum(i.quantity) desc, i.product_name
   limit least(greatest(coalesce(p_limit, 100), 1), 1000);
end;
$$;

revoke all on function public.admin_payments_summary() from public, anon;
grant execute on function public.admin_payments_summary() to authenticated;
revoke all on function public.admin_top_products(int) from public, anon;
grant execute on function public.admin_top_products(int) to authenticated;

commit;
