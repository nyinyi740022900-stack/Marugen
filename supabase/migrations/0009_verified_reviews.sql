-- Marugen Koi Farm — 0009: verified-purchase reviews + server-side stock.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)
--
-- 1. product_reviews: only customers who actually bought the product may
--    write a review. "Bought" = an order of theirs containing the product
--    whose status is paid or later (packing/shipped/delivered). Pending
--    (unpaid) and cancelled/refunded orders do not count.
-- 2. Stock is now decremented in the database when an order line is
--    inserted (live fish are flagged is_sold), and restored when the
--    customer/admin cancels the order. Before this, stock never changed
--    after a purchase, so a koi could be sold twice.

-- ---------------------------------------------------------------------
-- 1. Verified-purchase review policy
-- ---------------------------------------------------------------------
drop policy if exists "Users manage their own reviews" on public.product_reviews;

create policy "Verified buyers can insert their own reviews"
  on public.product_reviews for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.order_items oi
      join public.orders o on o.id = oi.order_id
      where oi.product_id = product_reviews.product_id
        and o.user_id = auth.uid()
        and o.status in ('paid', 'packing', 'shipped', 'delivered')
    )
  );

-- ---------------------------------------------------------------------
-- 2. Stock bookkeeping
-- ---------------------------------------------------------------------
create or replace function public.apply_order_item_stock()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_category text;
begin
  if new.product_id is null then
    return new;
  end if;

  if new.variant_id is not null then
    update public.product_variants
       set stock_quantity = greatest(0, stock_quantity - new.quantity)
     where id = new.variant_id;
  else
    select category into v_category from public.products where id = new.product_id;
    if v_category in ('koi', 'arowana') then
      -- A live fish is a single unique animal: mark it sold outright.
      update public.products
         set stock_quantity = 0, is_sold = true, updated_at = now()
       where id = new.product_id;
    else
      update public.products
         set stock_quantity = greatest(0, stock_quantity - new.quantity),
             updated_at = now()
       where id = new.product_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists order_items_apply_stock on public.order_items;
create trigger order_items_apply_stock
  after insert on public.order_items
  for each row execute function public.apply_order_item_stock();

-- Put stock back when an order is cancelled before it was delivered.
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

drop trigger if exists orders_restore_stock_on_cancel on public.orders;
create trigger orders_restore_stock_on_cancel
  after update of status on public.orders
  for each row execute function public.restore_stock_on_cancel();
