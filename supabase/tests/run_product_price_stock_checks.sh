#!/usr/bin/env bash
# Product price/stock checks (migration 0072). `--baseline` skips 0072 and
# should fail: S$0 prices and negative stock are accepted.
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
migration="$suite_dir/../migrations/0072_product_price_stock_checks.sql"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-price-checks.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${args[@]}" >"$test_root/bootstrap.log" <<'SQL'
create table public.products(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null,
  price numeric(10, 2),
  sale_price numeric(10, 2),
  stock_quantity int not null default 0
);
create table public.product_variants(
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  label text not null,
  price numeric(10, 2) not null,
  stock_quantity int not null default 0
);
-- A variant saved as S$0.00 by the old editor.
insert into public.products(id, name, category, price) values
('50000000-0000-0000-0000-0000000000f0', 'Old food', 'fish_food', 20);
insert into public.product_variants(product_id, label, price) values
('50000000-0000-0000-0000-0000000000f0', '1kg', 0);
SQL
if [[ "${1:-}" != '--baseline' ]]; then
  if psql "${args[@]}" -f "$migration" >"$test_root/blocked.log" 2>&1; then
    echo 'Migration accepted an existing S$0.00 variant' >&2
    exit 1
  fi
  grep -q 'Old food / 1kg' "$test_root/blocked.log"
  psql "${args[@]}" -c "update public.product_variants set price = 12 where label = '1kg'" >/dev/null
  psql "${args[@]}" -f "$migration" >>"$test_root/bootstrap.log"
  # Applying it again is harmless.
  psql "${args[@]}" -f "$migration" >>"$test_root/bootstrap.log"
fi
psql "${args[@]}" -f "$suite_dir/product_price_stock_checks.sql"
echo "product price/stock checks: all checks passed"
