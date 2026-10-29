#!/usr/bin/env bash
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-notifications.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
psql_args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${psql_args[@]}" >"$test_root/bootstrap.log" <<'SQL'
create role authenticated;
create schema auth;
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table public.profiles(id uuid primary key);
create table public.orders(id uuid primary key);
grant usage on schema public, auth to authenticated;
SQL
psql "${psql_args[@]}" -f "$suite_dir/../migrations/0016_notifications.sql" >>"$test_root/bootstrap.log"
if [[ "${1:-}" != '--baseline' ]]; then
  psql "${psql_args[@]}" -f "$suite_dir/../migrations/0065_notification_dismissal.sql" >>"$test_root/bootstrap.log"
fi
psql "${psql_args[@]}" -c 'grant select, update, delete on public.notifications to authenticated' >>"$test_root/bootstrap.log"
psql "${psql_args[@]}" -f "$suite_dir/notification_dismissal.sql"
