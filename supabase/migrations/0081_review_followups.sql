-- Marugen Koi Farm — 0081: follow-ups from the 2026-11-22 page review.
--
-- One self-contained file for the Supabase SQL editor. Safe to run again:
-- every statement is idempotent and the whole file is one transaction, so
-- a failure leaves the database exactly as it was.
--
-- Requires 0080. No Edge Function deploy is needed and none depends on
-- this file. The deployed app keeps working: no signature, column name,
-- column type, grant or notification key changes.
--
--   1. admin_payments_summary().transaction_count counted every order with
--      a Stripe PaymentIntent (abandoned and cancelled checkouts included),
--      so Home said "14 Stripe transactions" when 5 were paid. It now
--      counts exactly the orders that can contribute to `collected`:
--        a non-empty stripe_payment_intent_id, and
--        status in ('paid', 'packing', 'shipped', 'delivered')
--        or (status = 'refunded' and refund_status is not null
--            and refund_status <> 'succeeded').
--      `collected` is computed as before.
--
--   2. ops_monitor_findings(): the courier alert told staff to "Open the
--      order to check and finish it", but the order page has no staff
--      action; bookings are finished in Orders > Fulfillment. Only that
--      one body changes. Conditions, windows, titles and dedup keys are
--      those of 0080, so nothing already announced is announced again.
--      Notifications already in the inbox keep their old text.
--
--   3. A promo code that has redemptions can no longer be deleted by staff
--      or owner: the delete cascaded away promo_code_redemptions (0015),
--      which is the record of who used the code on which order, and the
--      one-use-per-customer rule with it. They turn the code off instead
--      (promo_codes.active = false, honoured by check_promo_code and
--      create-payment-intent since 0071). The service role and the
--      database owner are not restricted (same rule as the other guards,
--      0055 / 0057 / 0078), so maintenance scripts still work. Account
--      deletion never deletes a promo code (0051 keeps the redemption and
--      clears its user_id), and deleting an order still removes its own
--      redemption row; neither goes through this guard.
--
-- Rollback note (nothing here changes or drops existing data):
--   drop trigger if exists promo_codes_keep_redeemed on public.promo_codes;
--   drop function if exists public.guard_redeemed_promo_code_delete();
--   drop function if exists public.promo_code_has_redemptions(uuid);
--   alter table public.settings alter column gst_percent set default 9;
--   -- then re-run `create or replace function public.admin_payments_summary()`
--   -- from 0078_sprint3_hardening.sql and
--   -- `create or replace function public.ops_monitor_findings()` from
--   -- 0080_ops_monitoring.sql (grants are kept by create or replace).

begin;

-- ---------------------------------------------------------------------
-- 1. Payments summary: count only the orders behind the sum.
--    Same signature, columns, auth check and grants as 0078.
-- ---------------------------------------------------------------------
create or replace function public.admin_payments_summary()
returns table (transaction_count bigint, collected numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;
  return query
  select count(*),
         coalesce(sum(
           least(greatest(o.total - coalesce(o.refund_amount, 0), 0), o.total)
         ), 0)
    from public.orders o
   where nullif(o.stripe_payment_intent_id, '') is not null
     and (o.status in ('paid', 'packing', 'shipped', 'delivered')
          or (o.status = 'refunded'
              and o.refund_status is not null
              and o.refund_status <> 'succeeded'));
end;
$$;

revoke all on function public.admin_payments_summary() from public, anon;
grant execute on function public.admin_payments_summary() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Ops alerts: the courier body points at Orders > Fulfillment.
--    The function is 0080's, character for character, except that body.
-- ---------------------------------------------------------------------
create or replace function public.ops_monitor_findings()
returns table (
  condition text,
  order_id uuid,
  dedup_key text,
  since timestamptz,
  title text,
  body text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_day text := to_char(now() at time zone 'Asia/Singapore', 'YYYY-MM-DD');
  v_calls bigint;
  v_ok bigint;
  v_reason text;
  v_observable boolean := true;
begin
  -- 1. Payment not confirmed.
  return query
  select 'payment_not_confirmed'::text,
         o.id,
         'ops:payment_not_confirmed'::text,
         o.created_at + interval '45 minutes',
         'Payment not confirmed'::text,
         format('Order #%s has been waiting for payment for over 45 minutes. Check it in Stripe.',
                coalesce(o.order_number, left(o.id::text, 8)))
    from public.orders o
   where o.status = 'pending'
     and nullif(btrim(o.stripe_payment_intent_id), '') is not null
     and o.created_at < now() - interval '45 minutes';

  -- 2a. Refund failed or waiting for an action in Stripe. Keyed by the
  --     Stripe refund, so a second failed attempt is announced again.
  return query
  select 'refund_problem'::text,
         o.id,
         'ops:refund_' || o.refund_status || ':' || coalesce(r.stripe_refund_id, 'order'),
         coalesce(r.updated_at, now()),
         case o.refund_status
           when 'failed' then 'Refund failed'
           else 'Refund needs action'
         end,
         case o.refund_status
           when 'failed' then format(
             'A refund for order #%s failed. The customer has not been refunded. Check it in Stripe.',
             coalesce(o.order_number, left(o.id::text, 8)))
           else format(
             'A refund for order #%s needs action in Stripe before the customer gets the money.',
             coalesce(o.order_number, left(o.id::text, 8)))
         end
    from public.orders o
    left join lateral (
      select pr.stripe_refund_id, pr.updated_at
        from public.payment_refunds pr
       where pr.order_id = o.id and pr.status = o.refund_status
       order by pr.stripe_created_at desc, pr.stripe_refund_id desc
       limit 1
    ) r on true
   where o.refund_status in ('failed', 'requires_action');

  -- 2b. Refund pending for more than 24 hours (the reconcile job re-reads
  --     pending refunds from Stripe every 5 minutes).
  return query
  select 'refund_problem'::text,
         o.id,
         'ops:refund_pending:' || r.stripe_refund_id,
         r.stripe_created_at + interval '24 hours',
         'Refund still pending'::text,
         format('A refund for order #%s has been pending for over 24 hours. Check it in Stripe.',
                coalesce(o.order_number, left(o.id::text, 8)))
    from public.orders o
    join lateral (
      select pr.stripe_refund_id, pr.stripe_created_at
        from public.payment_refunds pr
       where pr.order_id = o.id and pr.status = 'pending'
       order by pr.stripe_created_at, pr.stripe_refund_id
       limit 1
    ) r on true
   where o.refund_status = 'pending'
     and r.stripe_created_at < now() - interval '24 hours';

  -- 5. Courier booking needs attention.
  return query
  select 'courier_needs_attention'::text,
         o.id,
         'ops:courier_needs_attention'::text,
         least(case when o.easyparcel_booking_state in ('booking', 'needs_attention')
                    then coalesce(o.easyparcel_booking_started_at, o.tracking_updated_at, o.created_at)
               end,
               p.since) + interval '30 minutes',
         'Courier booking needs attention'::text,
         format('The EasyParcel booking for order #%s did not complete. Open it in Orders › Fulfillment to finish it.',
                coalesce(o.order_number, left(o.id::text, 8)))
    from public.orders o
    left join lateral (
      select min(coalesce(op.tracking_updated_at, op.quote_expires_at, op.created_at)) as since
        from public.order_parcels op
       where op.order_id = o.id
         and op.state in ('booking', 'needs_attention', 'payment_required')
    ) p on true
   where o.status in ('paid', 'packing', 'shipped')
     and ((o.easyparcel_booking_state in ('booking', 'needs_attention')
           and coalesce(o.easyparcel_booking_started_at, o.tracking_updated_at, o.created_at)
               < now() - interval '30 minutes')
          or p.since < now() - interval '30 minutes');

  -- 6. EasyParcel disconnected. No row at all means it was never
  --    connected, which is a choice, not a fault.
  return query
  select 'easyparcel_disconnected'::text,
         null::uuid,
         'ops-daily:easyparcel_disconnected:' || v_day,
         c.refresh_token_expires_at,
         'EasyParcel disconnected'::text,
         'The EasyParcel connection has expired, so courier bookings will fail. Reconnect it in Settings.'::text
    from public.easyparcel_connection c
   where c.id = 1 and c.refresh_token_expires_at <= now();

  -- 3. Reconcile cron job. Checked last and guarded: whatever is wrong
  --    with cron, Vault or pg_net must not hide the findings above.
  begin
    if not exists (
      select 1 from cron.job j
       where j.jobname = 'reconcile-pending-orders'
         and coalesce((to_jsonb(j) ->> 'active')::boolean, true)
    ) then
      v_reason := 'The automatic Stripe payment check is not scheduled. Ask your developer to restore the reconcile-pending-orders cron job.';
    elsif (select count(distinct s.name) from vault.decrypted_secrets s
            where s.name in ('service_role_key', 'project_url')
              and s.decrypted_secret is not null) < 2 then
      v_reason := 'The automatic Stripe payment check is not set up: its Vault secrets are missing. Ask your developer to add them.';
    else
      -- Calls at least 2 minutes old have had time to be answered (pg_net
      -- gives up after a few seconds). A timeout, a network error and a
      -- missing answer all count as "no 2xx".
      select count(*), count(*) filter (where r.status_code between 200 and 299)
        into v_calls, v_ok
        from public.ops_cron_http_calls c
        left join net._http_response r on r.id = c.request_id
       where c.job = 'reconcile-pending-orders'
         and c.requested_at >= now() - interval '30 minutes'
         and c.requested_at < now() - interval '2 minutes';
      if v_calls >= 3 and v_ok = 0 then
        v_reason := 'The automatic Stripe payment check has failed for the last 30 minutes. Ask your developer to check the reconcile-pending-orders logs.';
      end if;
    end if;
  exception when others then
    v_observable := false;
    raise warning 'ops_monitor_findings: reconcile job could not be checked: %', sqlerrm;
  end;

  if not v_observable then
    return query
    select 'reconcile_unobservable'::text, null::uuid, null::text, now(), null::text, null::text;
  elsif v_reason is not null then
    return query
    select 'reconcile_failing'::text,
           null::uuid,
           'ops-daily:reconcile_failing:' || v_day,
           now(),
           'Payment check not running'::text,
           v_reason;
  end if;
end;
$$;

revoke all on function public.ops_monitor_findings() from public, anon, authenticated;
grant execute on function public.ops_monitor_findings() to service_role;

-- ---------------------------------------------------------------------
-- 3. A used promo code is turned off, not deleted.
--    The guard is INVOKER on purpose (as in 0052 / 0055): current_user
--    must be the calling database role. 23503 is the code PostgreSQL
--    itself uses for "still referenced"; the app already has wording.
--
--    The guard must not read promo_code_redemptions itself: as INVOKER it
--    would see only what the caller's RLS policies show ("Admins can view
--    promo redemptions", 0015), and if that policy were ever tightened or
--    dropped it would find nothing and let the delete cascade. The lookup
--    is therefore a SECURITY DEFINER helper that reads the table as its
--    owner, whatever the SELECT policies are.
--
--    The guard runs as the calling role, so that role needs EXECUTE on the
--    helper; `authenticated` has it and the helper authorises inside:
--      staff / owner  -> true or false
--      anyone else    -> null, the same for every code, so a customer
--                        cannot use it to learn whether a code was used
--      anon           -> no EXECUTE at all
--    The guard refuses on anything but a definite false, so a caller the
--    helper does not answer (or a role without EXECUTE) is stopped rather
--    than waved through.
-- ---------------------------------------------------------------------
create or replace function public.promo_code_has_redemptions(p_promo_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    return null;
  end if;
  return exists (select 1 from public.promo_code_redemptions r
                  where r.promo_code_id = p_promo_id);
end;
$$;

revoke all on function public.promo_code_has_redemptions(uuid) from public, anon, authenticated, service_role;
grant execute on function public.promo_code_has_redemptions(uuid) to authenticated;

create or replace function public.guard_redeemed_promo_code_delete()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_used boolean;
begin
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return old;
  end if;
  v_used := public.promo_code_has_redemptions(old.id);
  if v_used then
    raise exception 'This promo code has been used and cannot be deleted. Turn it off instead.'
      using errcode = '23503';
  elsif v_used is null then
    raise exception 'Only staff can delete promo codes' using errcode = '42501';
  end if;
  return old;
end;
$$;

revoke all on function public.guard_redeemed_promo_code_delete() from public, anon, authenticated;

drop trigger if exists promo_codes_keep_redeemed on public.promo_codes;
create trigger promo_codes_keep_redeemed
  before delete on public.promo_codes
  for each row execute function public.guard_redeemed_promo_code_delete();

-- 4. The shop is not GST-registered (owner, 2026-11-22): a missing or new
--    settings row must never default to charging 9%. The live row was set to
--    0 by hand the same day; this only changes the column default.
alter table public.settings alter column gst_percent set default 0;

commit;
