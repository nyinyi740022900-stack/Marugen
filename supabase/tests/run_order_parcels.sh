#!/usr/bin/env bash
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-delivery.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
psql_args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${psql_args[@]}" -f "$suite_dir/stock_review_bootstrap.sql" >"$test_root/bootstrap.log"
for migration in 0012_carrier_tracking 0042_easyparcel 0043_tracking_status_code 0052_stock_review_boundaries 0055_server_owned_order_financials 0056_allow_deleting_ordered_products; do
  psql "${psql_args[@]}" -f "$suite_dir/../migrations/$migration.sql" >>"$test_root/bootstrap.log"
done
sed 's/^rollback;/commit;/' "$suite_dir/shipping_finance_boundaries.sql" | (cd "$suite_dir"; psql "${psql_args[@]}")
psql "${psql_args[@]}" -f "$suite_dir/order_parcels.sql"
psql "${psql_args[@]}" -f "$suite_dir/tracking_progress.sql"
python3 "$suite_dir/order_parcels_race.py" "${psql_args[@]}"
