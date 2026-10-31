-- The product editor used to save a mistyped variant price as S$0.00 (which
-- checkout would then charge), a mistyped product price as NULL ("Contact for
-- price"), and negative stock. The app now validates the form; these checks
-- keep such values out even if a client or the SQL editor skips that.
--
-- Rows that already break a rule stop this migration with a list to fix in
-- the admin app first. A NOT VALID check would instead let them stay and make
-- every later update of those rows fail, including stock changes at checkout.

do $$
declare
  rows_to_fix text;
begin
  select string_agg(item, '; ' order by item)
    into rows_to_fix
    from (
      select format('%s (product %s)', p.name, p.id) as item
        from public.products p
       where p.price <= 0 or p.sale_price <= 0 or p.stock_quantity < 0
      union all
      select format('%s / %s (variant %s)', p.name, v.label, v.id)
        from public.product_variants v
        join public.products p on p.id = v.product_id
       where v.price <= 0 or v.stock_quantity < 0
    ) bad;
  if rows_to_fix is not null then
    raise exception 'Fix the price or stock of these items first: %', rows_to_fix;
  end if;
end;
$$;

alter table public.products
  drop constraint if exists products_price_positive,
  add constraint products_price_positive check (price is null or price > 0),
  drop constraint if exists products_sale_price_positive,
  add constraint products_sale_price_positive
    check (sale_price is null or sale_price > 0),
  drop constraint if exists products_stock_not_negative,
  add constraint products_stock_not_negative check (stock_quantity >= 0);

alter table public.product_variants
  drop constraint if exists product_variants_price_positive,
  add constraint product_variants_price_positive check (price > 0),
  drop constraint if exists product_variants_stock_not_negative,
  add constraint product_variants_stock_not_negative check (stock_quantity >= 0);
