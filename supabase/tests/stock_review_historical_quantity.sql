-- Proves 0052 can deploy without silently changing historical invalid data.
-- Run on the local bootstrap BEFORE 0052. The migration itself rolls back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values ('70000000-0000-0000-0000-000000000001','historical@example.invalid');
insert into public.orders(id,user_id) values ('70000000-0000-0000-0000-000000000002','70000000-0000-0000-0000-000000000001');
insert into public.order_items(id,order_id,product_name,quantity) values
('70000000-0000-0000-0000-000000000003','70000000-0000-0000-0000-000000000002','Historical snapshot',-3);
\ir ../migrations/0052_stock_review_boundaries.sql
do $$ begin
  if not exists(select 1 from public.order_items where id='70000000-0000-0000-0000-000000000003' and quantity=-3) then
    raise exception 'Historical invalid quantities were silently changed';
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.order_items'::regclass and conname='order_items_positive_quantity' and not convalidated) then
    raise exception 'Positive quantity constraint must defer historical validation';
  end if;
end $$;
rollback;
