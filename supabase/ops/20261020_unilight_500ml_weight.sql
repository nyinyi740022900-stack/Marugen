-- User correction: Uni-Light 500 ml counts as 500 g (0.5 kg).
-- Apply after 20261020_confirmed_shipping_weights.sql.
-- PetFran 2L and Hikari container remain at the confirmed 2 kg each.
begin;
do $$ begin
  if not exists (
    select 1 from public.products
    where id = 'a1000001-0000-4000-8000-000000000014'
      and category = 'accessories'
  ) or not exists (
    select 1 from public.product_variants
    where id = 'b1000001-0000-4000-8000-000000000037'
      and product_id = 'a1000001-0000-4000-8000-000000000014'
      and lower(replace(label, ' ', '')) = '500ml'
  ) then
    raise exception 'Expected Uni-Light 500ml product/variant changed; review first';
  end if;
end $$;
update public.products set shipping_weight_kg = 0.5
where id = 'a1000001-0000-4000-8000-000000000014';
update public.product_variants set shipping_weight_kg = 0.5
where id = 'b1000001-0000-4000-8000-000000000037';
commit;
