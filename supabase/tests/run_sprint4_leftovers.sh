#!/usr/bin/env bash
# Sprint 4 leftovers, checked against the FINAL schema: every migration
# 0001..0078 is applied in order on a fresh temporary local PostgreSQL
# cluster, then 0079 twice (it must be re-runnable).
#   easyparcel_lease_release.sql          migration 0079 (lease release RPC)
#   checkout_repeat_key_replacement.sql   no migration: the database rules
#       create-payment-intent relies on when it retires and replaces the
#       order of a repeated checkout key (one live order per key, one live
#       order per fish, stock and promo released exactly once).
# No app credentials, no TCP listener, never a deployed database.
#   --baseline  skip 0079; the lease checks should then fail (no release function).
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
migrations="$suite_dir/../migrations"
for executable in initdb pg_ctl psql; do
  command -v "$executable" >/dev/null || { echo "Missing local PostgreSQL executable: $executable" >&2; exit 1; }
done
# macOS refuses to start a postmaster under an unset or invalid locale.
export LC_ALL="${LC_ALL:-C}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-sprint4.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres --no-locale -E UTF8 >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
args=(-X -q -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
# Same stand-in for Supabase auth, storage, pg_cron, Vault and pg_net as the
# Sprint 1 suite.
psql "${args[@]}" -f "$suite_dir/sprint1_bootstrap.sql" >"$test_root/bootstrap.log" 2>&1 \
  || { cat "$test_root/bootstrap.log" >&2; exit 1; }

target="0079_easyparcel_refresh_lease_release.sql"
for migration in "$migrations"/[0-9][0-9][0-9][0-9]_*.sql; do
  name="$(basename -- "$migration")"
  [[ "$name" < "$target" ]] || continue
  # pg_cron and pg_net are not installed on a plain cluster; the bootstrap
  # provides the few objects the migrations use from them.
  sed -E 's/create extension if not exists (pg_cron|pg_net)[^;]*;//' "$migration" >"$test_root/migration.sql"
  psql "${args[@]}" -f "$test_root/migration.sql" >"$test_root/migration.log" 2>&1 \
    || { echo "Migration $name failed on the local cluster:" >&2; cat "$test_root/migration.log" >&2; exit 1; }
done

if [[ "${1:-}" != '--baseline' ]]; then
  psql "${args[@]}" -f "$migrations/$target" >"$test_root/0079-first.log" 2>&1 \
    || { cat "$test_root/0079-first.log" >&2; exit 1; }
  psql "${args[@]}" -f "$migrations/$target" >"$test_root/0079-second.log" 2>&1 \
    || { echo "0079 is not re-runnable:" >&2; cat "$test_root/0079-second.log" >&2; exit 1; }
fi
# Passing checks print nothing; a failed one stops with "FAILED: <what>".
psql "${args[@]}" -o /dev/null -f "$suite_dir/checkout_repeat_key_replacement.sql"
echo "checkout repeat-key replacement: all checks passed"
psql "${args[@]}" -o /dev/null -f "$suite_dir/easyparcel_lease_release.sql"
echo "easyparcel lease release (0079): all checks passed"
