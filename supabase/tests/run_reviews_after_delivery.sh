#!/usr/bin/env bash
# Reviews need a delivered order (migration 0075). `--baseline` skips 0075
# and should fail: a paid-but-undelivered order lets the customer review.
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-reviews.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${args[@]}" >"$test_root/bootstrap.log" <<'SQL'
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema public, auth to authenticated;
create table public.orders(id uuid primary key, user_id uuid, status text not null);
create table public.order_items(
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  product_id uuid
);
create table public.product_reviews(
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null,
  user_id uuid not null,
  rating int not null
);
alter table public.product_reviews enable row level security;
-- The rule from 0009_verified_reviews.sql that 0075 replaces.
create policy "Verified buyers can insert their own reviews"
  on public.product_reviews for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.order_items oi join public.orders o on o.id = oi.order_id
      where oi.product_id = product_reviews.product_id and o.user_id = auth.uid()
        and o.status in ('paid', 'packing', 'shipped', 'delivered')
    )
  );
grant select on public.orders, public.order_items to authenticated;
grant select, insert on public.product_reviews to authenticated;
insert into public.orders values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'paid'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000c1', 'delivered'),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000c1', 'refunded');
insert into public.order_items(order_id, product_id) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000f1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000f2'),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000f3');
SQL
if [[ "${1:-}" != '--baseline' ]]; then
  psql "${args[@]}" -f "$suite_dir/../migrations/0075_reviews_after_delivery.sql" >>"$test_root/bootstrap.log"
fi
psql "${args[@]}" >"$test_root/suite.log" <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$
declare
  product uuid;
  allowed text := '';
begin
  foreach product in array array[
    '00000000-0000-0000-0000-0000000000f1',
    '00000000-0000-0000-0000-0000000000f2',
    '00000000-0000-0000-0000-0000000000f3'
  ]::uuid[] loop
    begin
      insert into public.product_reviews(product_id, user_id, rating)
      values (product, '00000000-0000-0000-0000-0000000000c1', 5);
      allowed := allowed || right(product::text, 2) || ' ';
    exception when insufficient_privilege then null;
    end;
  end loop;
  if allowed <> 'f2 ' then
    raise exception 'Reviews allowed for: % (expected only the delivered f2)', allowed;
  end if;
end $$;
SQL
echo "reviews after delivery: all checks passed"
