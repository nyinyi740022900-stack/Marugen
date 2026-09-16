-- Marugen Koi Farm — 0010: payment integrity
-- Run with: supabase db push   (or paste into the Supabase SQL editor)
--
-- 1. One Stripe PaymentIntent maps to at most one order (idempotent webhooks).
-- 2. Stock apply is fail-closed: concurrent checkouts of the same live fish
--    or overselling a variant raise an exception instead of silently double-selling.

-- ---------------------------------------------------------------------
-- 1. Unique payment intent id (allow multiple NULLs for legacy rows)
-- ---------------------------------------------------------------------
create unique index if not exists orders_stripe_payment_intent_id_uidx
  on public.orders (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

-- ---------------------------------------------------------------------
-- 2. Hardening stock apply (atomic check + update)
-- ---------------------------------------------------------------------
create or replace function public.apply_order_item_stock()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_category text;
  v_updated int;
begin
  if new.product_id is null then
    return new;
  end if;

  if new.variant_id is not null then
    update public.product_variants
       set stock_quantity = stock_quantity - new.quantity
     where id = new.variant_id
       and stock_quantity >= new.quantity;
    get diagnostics v_updated = row_count;
    if v_updated = 0 then
      raise exception 'Insufficient variant stock for %', new.variant_id;
    end if;
  else
    select category into v_category from public.products where id = new.product_id;
    if v_category in ('koi', 'arowana') then
      update public.products
         set stock_quantity = 0, is_sold = true, updated_at = now()
       where id = new.product_id
         and is_sold = false
         and stock_quantity > 0;
      get diagnostics v_updated = row_count;
      if v_updated = 0 then
        raise exception 'Live fish already sold: %', new.product_id;
      end if;
    else
      update public.products
         set stock_quantity = stock_quantity - new.quantity,
             updated_at = now()
       where id = new.product_id
         and stock_quantity >= new.quantity;
      get diagnostics v_updated = row_count;
      if v_updated = 0 then
        raise exception 'Insufficient product stock for %', new.product_id;
      end if;
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Restore stock on cancel (also defined in 0009 — included here so
--    this file is safe to run alone in the SQL editor if 0009 was skipped)
-- ---------------------------------------------------------------------
create or replace function public.restore_stock_on_cancel()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  item record;
  v_category text;
begin
  if new.status = 'cancelled'
     and old.status in ('pending', 'paid', 'packing', 'shipped') then
    for item in
      select product_id, variant_id, quantity
        from public.order_items
       where order_id = new.id and product_id is not null
    loop
      if item.variant_id is not null then
        update public.product_variants
           set stock_quantity = stock_quantity + item.quantity
         where id = item.variant_id;
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
  end if;
  return new;
end;
$$;

-- Idempotent triggers
drop trigger if exists order_items_apply_stock on public.order_items;
create trigger order_items_apply_stock
  after insert on public.order_items
  for each row execute function public.apply_order_item_stock();

drop trigger if exists orders_restore_stock_on_cancel on public.orders;
create trigger orders_restore_stock_on_cancel
  after update of status on public.orders
  for each row execute function public.restore_stock_on_cancel();
