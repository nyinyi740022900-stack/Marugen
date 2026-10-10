-- Marugen Koi Farm — 0049: reconcile stale-pending orders against Stripe.
--
-- Companion to 0014_stale_order_cleanup.sql: that job blindly cancels any
-- order still `pending` after 30 minutes, assuming stripe-webhook never
-- fired. But if the webhook itself failed to reach Supabase (network blip,
-- brief outage) while the customer's card WAS actually charged, blind
-- cancellation would silently release the shop's stock (and a live fish's
-- `is_sold` flag) while the customer has already paid — a customer-visible,
-- money-losing bug with no automatic recovery.
--
-- Fix: a second scheduled job, running more often (every 5 minutes) and
-- with a much shorter window (5 minutes old) than the 30-minute cancel
-- job, that calls the `reconcile-pending-orders` Edge Function — which
-- asks Stripe directly whether each still-pending order's PaymentIntent
-- actually succeeded, and marks it `paid` itself if so (mirroring exactly
-- what stripe-webhook does) — rescuing it well before the cancel job ever
-- sees it.
--
-- Requires pg_net (for this cron job to call an Edge Function over HTTP)
-- and two Vault secrets so the call can authenticate as a service-role
-- caller, the same way stripe-webhook's own server-to-server calls do.
-- Vault secrets are NOT set here — their values are secrets and must never
-- be committed to a migration file. One-time manual setup, in the
-- Supabase SQL editor (or `supabase secrets`/Vault UI):
--
--   1. Database → Extensions → enable pg_net (or run the CREATE EXTENSION
--      below yourself if it's not already on).
--   2. select vault.create_secret('<SB_SERVICE_KEY or service_role JWT>', 'service_role_key');
--   3. select vault.create_secret('https://YOUR-PROJECT-REF.supabase.co', 'project_url');
--   4. Deploy the function: supabase functions deploy reconcile-pending-orders --no-verify-jwt
--
-- Until those Vault secrets exist, `reconcile_pending_orders()` below is a
-- silent no-op (logged via RAISE NOTICE) rather than a broken cron job —
-- cancel-stale-pending-orders still runs regardless, so nothing is worse
-- off than before this migration.

create extension if not exists pg_net with schema extensions;

create or replace function public.reconcile_pending_orders()
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_service_key text;
  v_project_url text;
begin
  select decrypted_secret into v_service_key from vault.decrypted_secrets where name = 'service_role_key';
  select decrypted_secret into v_project_url from vault.decrypted_secrets where name = 'project_url';

  if v_service_key is null or v_project_url is null then
    raise notice 'reconcile_pending_orders: service_role_key/project_url Vault secrets not configured yet, skipping';
    return;
  end if;

  perform net.http_post(
    url := v_project_url || '/functions/v1/reconcile-pending-orders',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
end;
$$;

select cron.unschedule(jobid)
  from cron.job
 where jobname = 'reconcile-pending-orders';

select cron.schedule(
  'reconcile-pending-orders',
  '*/5 * * * *', -- every 5 minutes — well inside the 30-minute cancel window
  $$select public.reconcile_pending_orders();$$
);
