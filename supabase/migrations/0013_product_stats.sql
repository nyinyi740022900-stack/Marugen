-- Marugen Koi Farm — 0013: product stats (sold count + review aggregate)
-- and a configurable delivery lead-time window shown on the shop grid.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)

alter table public.settings
  add column if not exists delivery_lead_days_min int not null default 2,
  add column if not exists delivery_lead_days_max int not null default 5;

-- security definer: sold counts need to read across every customer's
-- orders, and review aggregates need to see hidden-review rows too — both
-- are blocked by RLS for anon/authenticated callers, so this function runs
-- as its (postgres) owner instead. It only ever returns aggregated counts,
-- never individual order/review rows, so it doesn't leak anything RLS
-- would otherwise hide.
create or replace function public.get_product_stats()
returns table (
  product_id uuid,
  sold_count int,
  avg_rating numeric,
  review_count int
)
language sql
security definer
set search_path = public
stable
as $$
  select
    p.id as product_id,
    coalesce(sold.qty, 0)::int as sold_count,
    reviews.avg_rating,
    coalesce(reviews.review_count, 0)::int as review_count
  from public.products p
  left join (
    select oi.product_id, sum(oi.quantity) as qty
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where o.status in ('paid', 'packing', 'shipped', 'delivered')
    group by oi.product_id
  ) sold on sold.product_id = p.id
  left join (
    select product_id, avg(rating)::numeric(3, 2) as avg_rating, count(*)::int as review_count
    from public.product_reviews
    where is_hidden = false
    group by product_id
  ) reviews on reviews.product_id = p.id;
$$;

grant execute on function public.get_product_stats() to anon, authenticated;
