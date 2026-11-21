-- Marugen Koi Farm — 0079: release the EasyParcel token refresh lease early.
--
-- One self-contained file for the Supabase SQL editor. Safe to run again:
-- every statement is idempotent and the whole file is one transaction, so
-- a failure leaves the database exactly as it was.
--
-- Requires 0078 (easyparcel_connection.refresh_started_at and
-- claim_easyparcel_token_refresh). APPLY THIS BEFORE deploying the Edge
-- Functions that use _shared/easyparcel_token.ts from this change: the
-- token helper calls release_easyparcel_token_refresh() when a refresh
-- fails. (If the functions go first nothing breaks: the call fails, is
-- logged, and the lease simply expires after 60 seconds as before.)
--
-- Why: 0078 lets one request at a time refresh the token and makes the
-- lease expire by itself after 60 seconds. When EasyParcel rejected the
-- refresh or did not answer, the lease stayed held for those 60 seconds
-- although nobody was refreshing any more, and every other delivery
-- request answered "being refreshed, try again". The request that took
-- the lease now hands it back as soon as its refresh has failed.
--
-- Rollback note (nothing here changes or drops data):
--   drop function public.release_easyparcel_token_refresh(text);
--   (roll back the Edge Functions that use easyparcel_token.ts first, or
--   leave them: a missing function only means the lease expires by itself)

begin;

-- Hands the lease back. Returns true when a lease was released.
--   * Bound to the refresh token the lease was taken with (same rule as
--     the claim): once the tokens have been replaced, by a successful
--     refresh or by the admin reconnecting, an old holder releases nothing.
--   * Only a lease that is still running is released. An expired one is
--     already free for the next claim, and leaving it alone means a holder
--     that outlived its own lease cannot touch the row.
-- The Edge Function additionally calls this only shortly after its claim,
-- well inside the 60 seconds, so the lease it releases is its own: nobody
-- else can take the lease for the same refresh token before it expires.
create or replace function public.release_easyparcel_token_refresh(p_refresh_token text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_released int;
begin
  update public.easyparcel_connection
     set refresh_started_at = null
   where id = 1
     and refresh_token = p_refresh_token
     and refresh_started_at is not null
     and refresh_started_at >= now() - interval '60 seconds';
  get diagnostics v_released = row_count;
  return v_released = 1;
end;
$$;

-- Server only: the Edge Functions call it with the service-role key.
revoke all on function public.release_easyparcel_token_refresh(text)
  from public, anon, authenticated;
grant execute on function public.release_easyparcel_token_refresh(text) to service_role;

commit;
