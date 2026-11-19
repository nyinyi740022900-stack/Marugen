-- Marugen Koi Farm — 0077: Sprint 1 security and stock fixes.
--
-- One self-contained file for the Supabase SQL editor. Safe to run again:
-- every statement is idempotent and the whole file is one transaction, so
-- a failure leaves the database exactly as it was.
--
--   1. order_number_counters had no RLS and full API grants.
--   2. Server-only SECURITY DEFINER functions were executable by anyone.
--   3. Staff could change profile roles (their own included).
--   4. A full refund of an unshipped order never returned its stock.
--   5. The product-images bucket accepted any file type and size.
--
-- Rollback note (nothing here drops data):
--   1. alter table public.order_number_counters disable row level security;
--      grant all on public.order_number_counters to anon, authenticated;
--   2. grant execute on function <name> to public;   -- per function
--   3. re-run the function body from 0036_prevent_role_escalation.sql
--   4. re-run restore_stock_on_cancel() from 0020_variant_size_stocks.sql and
--      the trigger from 0010_payment_integrity.sql; order_stock_restorations
--      can stay (it is only a ledger) or be dropped
--   5. update storage.buckets set file_size_limit = null,
--      allowed_mime_types = null where id = 'product-images';

begin;

-- ---------------------------------------------------------------------
-- 1. order_number_counters: deny by default.
--    Only assign_order_number() (the BEFORE INSERT trigger on orders)
--    touches this table. It runs as its owner, so it keeps working with
--    RLS on and no policies. Re-assert that here in case of drift.
-- ---------------------------------------------------------------------
alter table public.order_number_counters enable row level security;
revoke all on table public.order_number_counters from public, anon, authenticated;
grant select, insert, update on table public.order_number_counters to service_role;

alter function public.assign_order_number() security definer;
alter function public.assign_order_number() set search_path = public;

-- ---------------------------------------------------------------------
-- 2. Server-only SECURITY DEFINER functions.
--    Supabase grants EXECUTE on new public functions to anon and
--    authenticated by default privilege, so revoking from PUBLIC alone is
--    not enough; all three are revoked.
--
--    Callers checked before revoking:
--      claim_promo_redemption / release_promo_redemption
--          create-payment-intent only, through its service-role client.
--          No trigger or SQL function calls them (restore_promo_on_cancel
--          does its own update).
--      cancel_stale_pending_orders / reconcile_pending_orders
--          pg_cron jobs only, which run as the job owner (postgres), the
--          owner of these functions. The owner keeps EXECUTE.
-- ---------------------------------------------------------------------
revoke all on function public.claim_promo_redemption(uuid) from public, anon, authenticated;
revoke all on function public.release_promo_redemption(uuid) from public, anon, authenticated;
revoke all on function public.cancel_stale_pending_orders() from public, anon, authenticated;
revoke all on function public.reconcile_pending_orders() from public, anon, authenticated;

grant execute on function public.claim_promo_redemption(uuid) to service_role;
grant execute on function public.release_promo_redemption(uuid) to service_role;
grant execute on function public.cancel_stale_pending_orders() to service_role;
grant execute on function public.reconcile_pending_orders() to service_role;

-- SECURITY DEFINER trigger functions. A trigger fires without checking the
-- writing user's EXECUTE privilege, and Postgres refuses to call a trigger
-- function directly, so removing the API grants cannot break any write.
-- Skips any that do not exist rather than failing the migration.
-- Deliberately NOT touched: is_admin() (RLS policies evaluate it as the
-- querying user) and the RPCs the app calls.
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.handle_new_user()',
    'public.apply_order_item_stock()',
    'public.restore_stock_on_cancel()',
    'public.restore_promo_on_cancel()',
    'public.validate_order_item_stock_input()',
    'public.assign_order_number()',
    'public.log_order_status_change()',
    'public.prevent_role_self_escalation()',
    'public.prevent_review_reassignment()',
    'public.update_order_fulfillment_snapshot()',
    'public.guard_support_contacts_owner()'
  ] loop
    if to_regprocedure(fn) is not null then
      execute format('revoke all on function %s from public, anon, authenticated', fn);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Role changes: owner only, and never on your own row.
--    0036 let any is_admin() caller (staff included) change a role.
--    A session with no user (service role, SQL editor, cron) is still
--    allowed, which is how owners are appointed today
--    (see supabase/ops/20261024_add_requested_owner.sql).
--    A disallowed change is silently reverted, as before, so an ordinary
--    profile edit that happens to send `role` still saves its other fields.
-- ---------------------------------------------------------------------
create or replace function public.prevent_role_self_escalation()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_caller_role text;
begin
  if new.role is distinct from old.role and v_caller is not null then
    -- The caller's role as stored now. In a BEFORE trigger this is still
    -- the value from before the current statement.
    select role into v_caller_role from public.profiles where id = v_caller;
    if v_caller_role is distinct from 'owner' or old.id = v_caller then
      new.role := old.role;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_role_self_escalation() from public, anon, authenticated;

drop trigger if exists trg_prevent_role_self_escalation on public.profiles;
create trigger trg_prevent_role_self_escalation
  before update on public.profiles
  for each row execute function public.prevent_role_self_escalation();

-- ---------------------------------------------------------------------
-- 4. Return stock when an unshipped order is fully refunded.
--    0053 forbids paid -> cancelled and 0059 moves a fully refunded order
--    to `refunded`, so the cancel-only trigger from 0020 never fired and a
--    refunded koi stayed is_sold forever.
--
--    Stock comes back on:
--      -> cancelled  from pending/paid/packing/shipped   (unchanged)
--      -> refunded   from paid/packing                    (new)
--    Not on a refund from shipped/delivered: the goods have left the shop.
--    Not on a partial refund: 0059 keeps the order's status as it was and
--    only sets refund_status = 'partially_refunded', so no status change
--    reaches this trigger until the refunds add up to the full total.
--
--    Exactly once: each restoration first claims a row in
--    order_stock_restorations (primary key = order). If the row already
--    exists nothing is restored, whatever path led here. Same idea as 0069,
--    where deleting the redemption row is the once-only marker.
-- ---------------------------------------------------------------------
create table if not exists public.order_stock_restorations (
  order_id uuid primary key references public.orders (id) on delete cascade,
  from_status text,
  to_status text not null check (to_status in ('cancelled', 'refunded')),
  -- auth.uid() of the session; null for the payment backend and cron.
  -- No foreign key, so deleting an account never touches this ledger.
  restored_by uuid,
  restored_at timestamptz not null default now()
);

comment on table public.order_stock_restorations is
  'One row per order whose reserved stock was returned. Written only by restore_stock_on_cancel(); its primary key is what stops a second restoration.';

alter table public.order_stock_restorations enable row level security;
revoke all on table public.order_stock_restorations from public, anon, authenticated;
grant select on table public.order_stock_restorations to authenticated;
grant select, insert on table public.order_stock_restorations to service_role;

drop policy if exists "Admins can view stock restorations" on public.order_stock_restorations;
create policy "Admins can view stock restorations"
  on public.order_stock_restorations for select to authenticated
  using (public.is_admin());

-- Orders cancelled before this migration already had their stock returned
-- by the old trigger; record that so the ledger is complete.
-- Orders refunded before this migration are NOT recorded and NOT restored
-- here: the shop may already have corrected that stock by hand. They are
-- terminal, so the trigger can never fire for them. See the pre-flight
-- query in the deployment notes for the list to review.
insert into public.order_stock_restorations (order_id, from_status, to_status, restored_at)
select o.id,
       (select h.from_status
          from public.order_status_history h
         where h.order_id = o.id and h.to_status = 'cancelled'
         order by h.changed_at desc
         limit 1),
       'cancelled',
       coalesce(
         (select max(h.changed_at)
            from public.order_status_history h
           where h.order_id = o.id and h.to_status = 'cancelled'),
         o.updated_at)
  from public.orders o
 where o.status = 'cancelled'
on conflict (order_id) do nothing;

-- Same restore loop as 0020; only the entry conditions changed.
create or replace function public.restore_stock_on_cancel()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  item record;
  v_category text;
  v_has_size_stocks boolean;
  v_claimed int;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if not (
       (new.status = 'cancelled' and old.status in ('pending', 'paid', 'packing', 'shipped'))
    or (new.status = 'refunded' and old.status in ('paid', 'packing'))
  ) then
    return new;
  end if;

  -- Claim the single restoration for this order. Zero rows means it was
  -- already restored: do nothing.
  insert into public.order_stock_restorations (order_id, from_status, to_status, restored_by)
  values (new.id, old.status, new.status, auth.uid())
  on conflict (order_id) do nothing;
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    return new;
  end if;

  for item in
    select product_id, variant_id, quantity, size_label
      from public.order_items
     where order_id = new.id and product_id is not null
  loop
    if item.variant_id is not null then
      select exists (
        select 1 from public.product_variant_size_stocks
         where variant_id = item.variant_id
      ) into v_has_size_stocks;

      if v_has_size_stocks
         and item.size_label is not null
         and btrim(item.size_label) <> '' then
        update public.product_variant_size_stocks
           set stock_quantity = stock_quantity + item.quantity
         where variant_id = item.variant_id
           and size_label = item.size_label;
      else
        update public.product_variants
           set stock_quantity = stock_quantity + item.quantity
         where id = item.variant_id;
      end if;
    else
      select category into v_category from public.products where id = item.product_id;
      if v_category in ('koi', 'arowana') then
        update public.products
           set stock_quantity = 1, is_sold = false, updated_at = now()
         where id = item.product_id;
      else
        update public.products
           set stock_quantity = stock_quantity + item.quantity,
               updated_at = now()
         where id = item.product_id;
      end if;
    end if;
  end loop;
  return new;
end;
$$;

revoke all on function public.restore_stock_on_cancel() from public, anon, authenticated;

drop trigger if exists orders_restore_stock_on_cancel on public.orders;
create trigger orders_restore_stock_on_cancel
  after update of status on public.orders
  for each row
  when (old.status is distinct from new.status
        and new.status in ('cancelled', 'refunded'))
  execute function public.restore_stock_on_cancel();

-- ---------------------------------------------------------------------
-- 5. product-images bucket limits.
--    The app uploads only still images here (product, variety, article,
--    service, banner photos and avatars/<uid>/...), resized by image_picker
--    to at most 1600 px at quality 85. Product videos are a pasted URL
--    (products.video_url), never an upload. The client sends no explicit
--    content type: it is derived from the file extension, so the list
--    covers every image extension a phone or browser picker returns.
--    SVG is left out on purpose (it can carry script, and customers can
--    write to avatars/). 10 MB leaves wide headroom over a resized photo
--    while stopping the bucket being used as free file hosting.
--    Existing objects are not affected; limits apply to new uploads only.
-- ---------------------------------------------------------------------
update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array[
         'image/jpeg',
         'image/png',
         'image/webp',
         'image/gif',
         'image/heic',
         'image/heif',
         'image/avif'
       ]
 where id = 'product-images';

commit;
