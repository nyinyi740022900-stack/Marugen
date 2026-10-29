-- User-confirmed 2026-10-20: all three packaged items weigh 2 kg each.
do $$ begin
 if (select count(*) from public.products where id in ('a1000001-0000-4000-8000-000000000014','a1000001-0000-4000-8000-000000000015','a1000001-0000-4000-8000-000000000016') and category='accessories')<>3 then
 raise exception 'Expected three confirmed accessories are missing'; end if;
 if (select count(*) from public.product_variants where product_id in ('a1000001-0000-4000-8000-000000000014','a1000001-0000-4000-8000-000000000015'))<>2 then
 raise exception 'Expected liquid variants changed; review before setting weight'; end if;
end $$;
update public.products set shipping_weight_kg=2 where id in ('a1000001-0000-4000-8000-000000000014','a1000001-0000-4000-8000-000000000015','a1000001-0000-4000-8000-000000000016');
update public.product_variants set shipping_weight_kg=2 where product_id in ('a1000001-0000-4000-8000-000000000014','a1000001-0000-4000-8000-000000000015');
