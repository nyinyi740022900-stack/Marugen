-- Weight × size inventory for restockable goods.
-- Price stays on product_variants (weight); stock for each pellet size
-- lives here when products.size_options is non-empty.

create table if not exists public.product_variant_size_stocks (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  size_label text not null,
  stock_quantity int not null default 0 check (stock_quantity >= 0),
  created_at timestamptz not null default now(),
  unique (variant_id, size_label)
);

create index if not exists product_variant_size_stocks_variant_idx
  on public.product_variant_size_stocks (variant_id);

alter table public.product_variant_size_stocks enable row level security;

drop policy if exists "Anyone can view variant size stocks"
  on public.product_variant_size_stocks;
create policy "Anyone can view variant size stocks"
  on public.product_variant_size_stocks for select using (true);

drop policy if exists "Admins can manage variant size stocks"
  on public.product_variant_size_stocks;
create policy "Admins can manage variant size stocks"
  on public.product_variant_size_stocks for all
  using (public.is_admin()) with check (public.is_admin());

-- Fail-closed stock apply: when an order line has size_label and that
-- variant has a size-stock matrix, decrement the matrix cell. Otherwise
-- keep the legacy weight-level product_variants.stock_quantity path.
create or replace function public.apply_order_item_stock()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_category text;
  v_updated int;
  v_has_size_stocks boolean;
begin
  if new.product_id is null then
    return new;
  end if;

  if new.variant_id is not null then
    select exists (
      select 1 from public.product_variant_size_stocks
       where variant_id = new.variant_id
    ) into v_has_size_stocks;

    if v_has_size_stocks then
      if new.size_label is null or btrim(new.size_label) = '' then
        raise exception 'Size required for variant %', new.variant_id;
      end if;
      update public.product_variant_size_stocks
         set stock_quantity = stock_quantity - new.quantity
       where variant_id = new.variant_id
         and size_label = new.size_label
         and stock_quantity >= new.quantity;
      get diagnostics v_updated = row_count;
      if v_updated = 0 then
        raise exception 'Insufficient size stock for % / %',
          new.variant_id, new.size_label;
      end if;
    else
      update public.product_variants
         set stock_quantity = stock_quantity - new.quantity
       where id = new.variant_id
         and stock_quantity >= new.quantity;
      get diagnostics v_updated = row_count;
      if v_updated = 0 then
        raise exception 'Insufficient variant stock for %', new.variant_id;
      end if;
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

create or replace function public.restore_stock_on_cancel()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  item record;
  v_category text;
  v_has_size_stocks boolean;
begin
  if new.status = 'cancelled'
     and old.status in ('pending', 'paid', 'packing', 'shipped') then
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
  end if;
  return new;
end;
$$;
