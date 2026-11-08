-- Run with psql after migration 0074 (tables come from the runner).
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id, role) values
  ('00000000-0000-0000-0000-0000000000c1', 'customer'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner');
insert into public.orders(status, total, refund_amount, created_at) values
  ('pending', 50, null, now()),
  ('paid', 100, null, now()),
  ('shipped', 200, null, now() - interval '10 days'),
  ('refunded', 80, 30, now()),
  ('cancelled', 70, null, now());
-- More orders than PostgREST would ever return in one response.
insert into public.orders(status, total, created_at)
select 'delivered', 1, now() - interval '20 days' from generate_series(1, 1500);

create temporary table sgt as
select (now() at time zone 'Asia/Singapore')::date as today;
insert into public.app_visits(visited_at)
select ((select today from sgt) - 2 + time '12:00') at time zone 'Asia/Singapore'
  from generate_series(1, 1500);
insert into public.app_visits(visited_at)
select ((select today from sgt) + time '00:30') at time zone 'Asia/Singapore'
  from generate_series(1, 3);
insert into public.products(id, name) values
  ('00000000-0000-0000-0000-0000000000f1', 'Kohaku'),
  ('00000000-0000-0000-0000-0000000000f2', 'Fish food');
-- 07:30 in Singapore is still the previous day in UTC.
insert into public.product_views(product_id, viewed_at)
select '00000000-0000-0000-0000-0000000000f1',
       ((select today from sgt) - 1 + time '07:30') at time zone 'Asia/Singapore'
  from generate_series(1, 5);
insert into public.product_views(product_id, viewed_at) values
  ('00000000-0000-0000-0000-0000000000f2', now()),
  ('00000000-0000-0000-0000-0000000000f2', now()),
  (null, now());

-- Customers cannot read shop totals.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
do $$ begin
  begin
    perform public.admin_order_summary();
    raise exception 'Customer read the order summary';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_daily_activity(7);
    raise exception 'Customer read app activity';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
do $$
declare
  s record;
  days text;
  top text;
begin
  select * into strict s from public.admin_order_summary();
  if s.open_orders <> 2 or s.total_revenue <> 1850 or s.week_revenue <> 150 then
    raise exception 'Order summary wrong: %', row_to_json(s);
  end if;
  select string_agg(format('%s/%s', visits, product_views), ' ' order by day)
    into days from public.admin_daily_activity(3);
  if days <> '1500/0 0/5 3/3' then
    raise exception 'Daily activity wrong: %', days;
  end if;
  select string_agg(format('%s=%s', coalesce(product_name, '?'), views), ' ')
    into top from public.admin_top_viewed_products(now() - interval '7 days', 10);
  if top <> 'Kohaku=5 Fish food=2 ?=1' then
    raise exception 'Top viewed products wrong: %', top;
  end if;
end $$;
rollback;
