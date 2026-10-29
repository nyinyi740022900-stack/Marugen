#!/usr/bin/env bash
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-promo.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${args[@]}" >"$test_root/bootstrap.log" <<'SQL'
create table public.promo_codes(id uuid primary key, code text, max_redemptions int, times_redeemed int not null default 0);
create table public.orders(id uuid primary key, status text, promo_code text);
create table public.promo_code_redemptions(id uuid primary key default gen_random_uuid(),
  promo_code_id uuid references public.promo_codes on delete cascade, user_id uuid,
  order_id uuid references public.orders on delete cascade, unique(promo_code_id, user_id));
-- Pre-existing data: one order refunded before the fix still holds its slot.
insert into public.promo_codes values ('00000000-0000-0000-0000-0000000000a1','OLD',1,1);
insert into public.orders values ('00000000-0000-0000-0000-0000000000b1','refunded','OLD');
insert into public.promo_code_redemptions(promo_code_id,user_id,order_id)
  values ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000b1');
SQL
psql "${args[@]}" -f "$suite_dir/../migrations/0069_release_promo_on_refund.sql" >>"$test_root/bootstrap.log"
psql "${args[@]}" -f "$suite_dir/promo_release.sql"
echo "promo release: all checks passed"
