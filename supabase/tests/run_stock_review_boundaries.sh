#!/usr/bin/env bash
# Uses only a fresh temporary local PostgreSQL cluster; no app credentials.
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for executable in initdb pg_ctl psql python3; do
  command -v "$executable" >/dev/null || { echo "Missing local PostgreSQL executable: $executable" >&2; exit 1; }
done
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-boundaries.XXXXXX")"
cleanup() {
  pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf -- "$test_root"
}
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
# No TCP listener. The private socket directory isolates this cluster.
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
psql_args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${psql_args[@]}" -f "$suite_dir/stock_review_bootstrap.sql" >"$test_root/bootstrap.log"
if [[ "${1:-}" != '--baseline' ]]; then
  psql "${psql_args[@]}" -f "$suite_dir/stock_review_historical_quantity.sql"
  psql "${psql_args[@]}" -f "$suite_dir/../migrations/0052_stock_review_boundaries.sql"
fi
psql "${psql_args[@]}" -f "$suite_dir/stock_review_boundaries.sql"
if [[ "${1:-}" != '--payment-baseline' ]]; then
  psql "${psql_args[@]}" -f "$suite_dir/../migrations/0053_verified_payment_cancellation.sql"
fi
psql "${psql_args[@]}" -f "$suite_dir/verified_payment_cancellation.sql"

if [[ "${1:-}" != '--idempotency-baseline' ]]; then
  psql "${psql_args[@]}" -v setup=true -f "$suite_dir/checkout_idempotency_historical_duplicates.sql"
  if psql "${psql_args[@]}" -f "$suite_dir/../migrations/0054_checkout_idempotency.sql" >"$test_root/duplicate-migration.log" 2>&1; then
    echo 'Migration accepted historical duplicate checkout keys unexpectedly' >&2
    exit 1
  fi
  psql "${psql_args[@]}" -v setup=false -f "$suite_dir/checkout_idempotency_historical_duplicates.sql"
  psql "${psql_args[@]}" -f "$suite_dir/../migrations/0054_checkout_idempotency.sql"
fi
psql "${psql_args[@]}" -f "$suite_dir/checkout_idempotency.sql"
psql "${psql_args[@]}" -f "$suite_dir/../migrations/0055_server_owned_order_financials.sql"
psql "${psql_args[@]}" -f "$suite_dir/server_owned_financials.sql"

psql "${psql_args[@]}" -f "$suite_dir/../migrations/0059_verified_async_refunds.sql"
psql "${psql_args[@]}" -f "$suite_dir/refund_lifecycle.sql"

python3 "$suite_dir/reservation_cancel_race.py" "$test_root"
