#!/usr/bin/env bash
# Sprint 1 security fixes (migration 0077), checked against the FINAL schema:
# every migration 0001..0076 is applied in order on a fresh temporary local
# PostgreSQL cluster, then 0077 twice (it must be re-runnable).
# No app credentials, no TCP listener, never a deployed database.
#   --baseline  skip 0077; the checks should then fail on the original gaps.
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
migrations="$suite_dir/../migrations"
for executable in initdb pg_ctl psql; do
  command -v "$executable" >/dev/null || { echo "Missing local PostgreSQL executable: $executable" >&2; exit 1; }
done
# macOS refuses to start a postmaster under an unset or invalid locale.
export LC_ALL="${LC_ALL:-C}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-sprint1.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres --no-locale -E UTF8 >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
args=(-X -q -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${args[@]}" -f "$suite_dir/sprint1_bootstrap.sql" >"$test_root/bootstrap.log" 2>&1 \
  || { cat "$test_root/bootstrap.log" >&2; exit 1; }

target="0077_sprint1_security_fixes.sql"
for migration in "$migrations"/[0-9][0-9][0-9][0-9]_*.sql; do
  name="$(basename -- "$migration")"
  [[ "$name" < "$target" ]] || continue
  # pg_cron and pg_net are not installed on a plain cluster; the bootstrap
  # provides the few objects the migrations use from them.
  sed -E 's/create extension if not exists (pg_cron|pg_net)[^;]*;//' "$migration" >"$test_root/migration.sql"
  psql "${args[@]}" -f "$test_root/migration.sql" >"$test_root/migration.log" 2>&1 \
    || { echo "Migration $name failed on the local cluster:" >&2; cat "$test_root/migration.log" >&2; exit 1; }
done

psql "${args[@]}" -f "$suite_dir/sprint1_security_fixes_fixture.sql" >/dev/null
if [[ "${1:-}" != '--baseline' ]]; then
  psql "${args[@]}" -f "$migrations/$target" >"$test_root/0077-first.log" 2>&1 \
    || { cat "$test_root/0077-first.log" >&2; exit 1; }
  psql "${args[@]}" -f "$migrations/$target" >"$test_root/0077-second.log" 2>&1 \
    || { echo "0077 is not re-runnable:" >&2; cat "$test_root/0077-second.log" >&2; exit 1; }
fi
# Passing checks print nothing; a failed one stops with "FAILED: <what>".
psql "${args[@]}" -o /dev/null -f "$suite_dir/sprint1_security_fixes.sql"
echo "sprint 1 security fixes: all checks passed"
