-- Local PostgreSQL only: the minimum of Supabase (roles, auth, storage,
-- pg_cron, Vault, pg_net, realtime) needed to apply every migration in
-- order on a plain cluster. Nothing here talks to a network.
\set ON_ERROR_STOP on
set client_min_messages = warning;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema storage;
create schema extensions;
create schema cron;
create schema vault;
create schema net;
create table auth.users (
  id uuid primary key, email text, raw_user_meta_data jsonb,
  last_sign_in_at timestamptz
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.role', true), '');
$$;
create table storage.buckets (
  id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
  id uuid default gen_random_uuid(), bucket_id text, name text, owner uuid,
  metadata jsonb
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1];
$$;
create table cron.job (jobid bigserial primary key, jobname text, schedule text, command text);
create function cron.schedule(text, text, text) returns bigint language sql as $$
  insert into cron.job (jobname, schedule, command) values ($1, $2, $3) returning jobid;
$$;
create function cron.unschedule(bigint) returns boolean language sql as $$
  delete from cron.job where jobid = $1 returning true;
$$;
create table vault.decrypted_secrets (name text, decrypted_secret text);
create function net.http_post(url text, headers jsonb, body jsonb) returns bigint
language sql as $$ select 1::bigint; $$;
create publication supabase_realtime;
grant usage on schema auth, public, storage, extensions to anon, authenticated, service_role;
-- Supabase's default privileges: every new object in public is reachable by
-- the API roles unless a migration revokes it. Without this the suite could
-- not tell a real revoke from a grant that was never there.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
