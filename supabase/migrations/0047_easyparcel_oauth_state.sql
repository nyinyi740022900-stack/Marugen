-- Single-use, short-lived OAuth `state` values for the EasyParcel connect
-- flow. Previously the Flutter app generated a random `state` and sent it
-- to EasyParcel's authorize URL, but never persisted it anywhere, and
-- easyparcel-oauth-callback never read it back — so the callback accepted
-- ANY `code` for ANY EasyParcel account, with nothing binding the request
-- to the admin session that started it (classic OAuth CSRF/account-
-- substitution gap). Now easyparcel-oauth-start (admin-only) generates and
-- stores the state here; easyparcel-oauth-callback must find it, and
-- deletes it immediately (single-use) whether the exchange succeeds or not.
--
-- RLS enabled with NO policies for any client role — only service-role
-- Edge Functions (which bypass RLS) ever read/write this table.
create table if not exists public.easyparcel_oauth_state (
  state text primary key,
  created_at timestamptz not null default now()
);
alter table public.easyparcel_oauth_state enable row level security;
