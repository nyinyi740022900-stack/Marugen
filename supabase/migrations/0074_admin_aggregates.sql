-- Server-side totals for the admin dashboard and analytics
-- (whole-app audit P1-5 and D1).
--
-- Both screens added up raw rows in the app. PostgREST returns at most
-- 1000 rows, so totals silently stopped growing; the dashboard also
-- followed the Orders tab's status filter, counted unpaid orders as
-- revenue and ignored partial refunds.

-- Open orders (unpaid or waiting to pack) and revenue: paid orders and
-- later stages, less verified refunds. "Week" is the last 7 days.
create or replace function public.admin_order_summary()
returns table (open_orders bigint, total_revenue numeric, week_revenue numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  return query
  select count(*) filter (where o.status in ('pending', 'paid')),
         coalesce(sum(o.total - coalesce(o.refund_amount, 0)) filter (
           where o.status in ('paid', 'packing', 'shipped', 'delivered', 'refunded')
         ), 0),
         coalesce(sum(o.total - coalesce(o.refund_amount, 0)) filter (
           where o.status in ('paid', 'packing', 'shipped', 'delivered', 'refunded')
             and o.created_at >= now() - interval '7 days'
         ), 0)
    from public.orders o;
end;
$$;

-- App opens and product views per Singapore day, oldest first, with a
-- zero row for quiet days. At most 400 days.
create or replace function public.admin_daily_activity(p_days int default 190)
returns table (day date, visits bigint, product_views bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  span int := least(greatest(coalesce(p_days, 190), 1), 400);
  today date := (now() at time zone 'Asia/Singapore')::date;
  since timestamptz := (today - (span - 1))::timestamp at time zone 'Asia/Singapore';
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  return query
  with days as (
    select generate_series(today - (span - 1), today, interval '1 day')::date as day
  ),
  v as (
    select (a.visited_at at time zone 'Asia/Singapore')::date as day, count(*) as n
      from public.app_visits a
     where a.visited_at >= since
     group by 1
  ),
  pv as (
    select (p.viewed_at at time zone 'Asia/Singapore')::date as day, count(*) as n
      from public.product_views p
     where p.viewed_at >= since
     group by 1
  )
  select d.day, coalesce(v.n, 0), coalesce(pv.n, 0)
    from days d
    left join v on v.day = d.day
    left join pv on pv.day = d.day
   order by d.day;
end;
$$;

-- Most viewed products since a moment; deleted products show no name.
create or replace function public.admin_top_viewed_products(
  p_since timestamptz,
  p_limit int default 10
)
returns table (product_id uuid, product_name text, views bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  return query
  select v.product_id, p.name, count(*)
    from public.product_views v
    left join public.products p on p.id = v.product_id
   where v.viewed_at >= p_since
   group by v.product_id, p.name
   order by count(*) desc, p.name nulls last
   limit least(greatest(coalesce(p_limit, 10), 1), 50);
end;
$$;

revoke all on function public.admin_order_summary() from public, anon;
grant execute on function public.admin_order_summary() to authenticated;
revoke all on function public.admin_daily_activity(int) from public, anon;
grant execute on function public.admin_daily_activity(int) to authenticated;
revoke all on function public.admin_top_viewed_products(timestamptz, int)
  from public, anon;
grant execute on function public.admin_top_viewed_products(timestamptz, int)
  to authenticated;
