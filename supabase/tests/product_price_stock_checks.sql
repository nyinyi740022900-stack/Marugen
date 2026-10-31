-- Run with psql after migration 0072. All fixtures are rolled back.
\set ON_ERROR_STOP on
begin;
create temporary table results (label text, passed boolean);
create function pg_temp.rejects(label text, statement text) returns void
language plpgsql as $$
declare rejected boolean := false;
begin
  begin
    execute statement;
  exception when check_violation then
    rejected := true;
  end;
  insert into results values (label, rejected);
end;
$$;
create function pg_temp.accepts(label text, statement text) returns void
language plpgsql as $$
declare accepted boolean := true;
begin
  begin
    execute statement;
  exception when others then
    accepted := false;
  end;
  insert into results values (label, accepted);
end;
$$;

insert into public.products(id, name, category, price, stock_quantity) values
('50000000-0000-0000-0000-000000000001', 'Checks food', 'fish_food', 10, 3);

select pg_temp.rejects('S$0 product price',
  $q$insert into public.products(name, category, price) values ('Free', 'fish_food', 0)$q$);
select pg_temp.rejects('negative product price',
  $q$update public.products set price = -5 where name = 'Checks food'$q$);
select pg_temp.accepts('no price stays allowed (contact for price)',
  $q$insert into public.products(name, category, price) values ('Ask us', 'koi', null)$q$);
select pg_temp.rejects('S$0 sale price',
  $q$update public.products set sale_price = 0 where name = 'Checks food'$q$);
select pg_temp.accepts('real sale price',
  $q$update public.products set sale_price = 8 where name = 'Checks food'$q$);
select pg_temp.rejects('negative product stock',
  $q$update public.products set stock_quantity = -1 where name = 'Checks food'$q$);
select pg_temp.accepts('selling the last items leaves zero stock',
  $q$update public.products set stock_quantity = stock_quantity - 3
      where name = 'Checks food' and stock_quantity >= 3$q$);
select pg_temp.rejects('S$0 variant price',
  $q$insert into public.product_variants(product_id, label, price)
     values ('50000000-0000-0000-0000-000000000001', '1kg', 0)$q$);
select pg_temp.rejects('negative variant stock',
  $q$insert into public.product_variants(product_id, label, price, stock_quantity)
     values ('50000000-0000-0000-0000-000000000001', '2kg', 12, -2)$q$);
select pg_temp.accepts('valid variant',
  $q$insert into public.product_variants(product_id, label, price, stock_quantity)
     values ('50000000-0000-0000-0000-000000000001', '5kg', 18.9, 4)$q$);

do $$
declare failed text;
begin
  select string_agg(label, ', ') into failed from results where not passed;
  if failed is not null then
    raise exception 'Product price/stock checks failed: %', failed;
  end if;
end;
$$;
rollback;
