#!/usr/bin/env bash
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-support.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${args[@]}" >"$test_root/bootstrap.log" <<'SQL'
create role authenticated;
create role service_role;
create schema auth;
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.role() returns text language sql stable as
$$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;
create table public.profiles(id uuid primary key, role text);
create table public.settings(id int primary key, shop_name text, support_contacts jsonb not null default '[]');
insert into public.settings values (1, 'Shop', '[]');
insert into public.profiles values ('00000000-0000-0000-0000-000000000001','owner'), ('00000000-0000-0000-0000-000000000002','staff');
grant usage on schema public, auth to authenticated, service_role;
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.settings to authenticated, service_role;
SQL
if [[ "${1:-}" != '--baseline' ]]; then
 psql "${args[@]}" -f "$suite_dir/../migrations/0067_support_contacts.sql" >>"$test_root/bootstrap.log"
fi
psql "${args[@]}" -f "$suite_dir/support_contacts.sql"
