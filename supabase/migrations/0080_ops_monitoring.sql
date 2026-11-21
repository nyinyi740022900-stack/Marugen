-- Marugen Koi Farm — 0080: operational monitoring.
--
-- One self-contained file for the Supabase SQL editor. Safe to run again:
-- every statement is idempotent and the whole file is one transaction, so
-- a failure leaves the database exactly as it was.
--
-- Requires 0079 and the pg_cron / pg_net setup of 0014 and 0049. No Edge
-- Function deploy is needed and none depends on this file.
--
-- Why: when a payment, refund or courier booking got stuck, nobody was
-- told. Every 15 minutes ops_monitor_run() now looks for the problems
-- below and writes ONE inbox notification per problem to every staff and
-- owner account (never to customers). The same rules feed
-- admin_ops_health(), a count per condition for the dashboard.
--
--   payment_not_confirmed    order still `pending` with a Stripe
--                            PaymentIntent 45 minutes after checkout: the
--                            webhook and the 5-minute reconcile job both
--                            failed to settle it.
--   refund_problem           orders.refund_status is 'failed' or
--                            'requires_action', or 'pending' with a Stripe
--                            refund created more than 24 hours ago.
--   reconcile_failing        the reconcile-pending-orders cron job is not
--                            scheduled, its Vault secrets are missing, or
--                            none of its HTTP calls in the last 30 minutes
--                            got a 2xx answer.
--   courier_needs_attention  an EasyParcel booking (order or parcel) left
--                            in needs_attention / payment_required, or
--                            stuck in `booking`, for 30 minutes.
--   easyparcel_disconnected  the stored EasyParcel refresh token has
--                            expired (the rule easyparcel-status uses).
--
-- Not covered, because the data cannot tell:
--   * "paid by the reconcile job, not the webhook": both go through the
--     same service-role update; order_status_history.changed_by is null
--     for both.
--   * "EasyParcel refresh is failing": a failed refresh is only logged by
--     the Edge Function; nothing is stored.
--
-- Spam control:
--   * order problems use the existing unique index
--     notifications (order_id, user_id, key): one row per order, staff
--     member and problem, for good (dismissed rows still count);
--   * the two shop-wide problems carry the Singapore date in their key and
--     a new partial unique index, so at most one reminder a day;
--   * nothing that became a problem more than 7 days ago is announced, so
--     applying this file does not flood the inbox with old leftovers
--     (admin_ops_health() still counts them).
--
-- Push: these rows reach the app through the inbox (and Realtime, 0038).
-- A push is sent only by Edge Functions (_shared/push.ts), and none is
-- called here.
--
-- Rollback note (nothing here changes or drops existing data):
--   select cron.unschedule(jobid) from cron.job where jobname = 'ops-monitor';
--   drop function public.admin_ops_health();
--   drop function public.ops_monitor_run();
--   drop function public.ops_monitor_findings();
--   -- then re-run the body of reconcile_pending_orders() from
--   -- 0049_reconcile_pending_orders.sql (it only stops recording ids), and:
--   drop table public.ops_cron_http_calls;
--   drop index public.notifications_ops_daily_user_key_uidx;
--   drop index public.orders_refund_status_open_idx;
--   drop index public.orders_easyparcel_booking_open_idx;
--   -- Notifications already written stay in the inbox; to remove them:
--   -- delete from public.notifications where key like 'ops:%' or key like 'ops-daily:%';

begin;

-- ---------------------------------------------------------------------
-- 1. Which pg_net request belongs to the reconcile cron job.
--    net._http_response has no URL, and 0049 threw the request id away,
--    so "cron succeeded" said nothing about the HTTP call. The id is now
--    kept here; rows older than 7 days are pruned by ops_monitor_run().
--    Server only: RLS on, no policies, no API grants.
-- ---------------------------------------------------------------------
create table if not exists public.ops_cron_http_calls (
  request_id bigint primary key,
  job text not null,
  requested_at timestamptz not null default now()
);
create index if not exists ops_cron_http_calls_job_requested_at_idx
  on public.ops_cron_http_calls (job, requested_at desc);
alter table public.ops_cron_http_calls enable row level security;
revoke all on table public.ops_cron_http_calls from public, anon, authenticated;
grant select, insert, update, delete on table public.ops_cron_http_calls to service_role;

-- Same function as 0049 (its only definition): the HTTP call is unchanged,
-- its request id is additionally recorded. Recording can never break the
-- call: it happens afterwards and any error is downgraded to a warning.
create or replace function public.reconcile_pending_orders()
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_service_key text;
  v_project_url text;
  v_request_id bigint;
begin
  select decrypted_secret into v_service_key from vault.decrypted_secrets where name = 'service_role_key';
  select decrypted_secret into v_project_url from vault.decrypted_secrets where name = 'project_url';

  if v_service_key is null or v_project_url is null then
    raise notice 'reconcile_pending_orders: service_role_key/project_url Vault secrets not configured yet, skipping';
    return;
  end if;

  v_request_id := net.http_post(
    url := v_project_url || '/functions/v1/reconcile-pending-orders',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );

  begin
    insert into public.ops_cron_http_calls (request_id, job)
    values (v_request_id, 'reconcile-pending-orders')
    on conflict (request_id) do update
      set job = excluded.job, requested_at = now();
  exception when others then
    raise warning 'reconcile_pending_orders: request id not recorded: %', sqlerrm;
  end;
end;
$$;

revoke all on function public.reconcile_pending_orders() from public, anon, authenticated;
grant execute on function public.reconcile_pending_orders() to service_role;

-- ---------------------------------------------------------------------
-- 2. Indexes for the two filters that had none.
-- ---------------------------------------------------------------------
create index if not exists orders_refund_status_open_idx
  on public.orders (refund_status)
  where refund_status in ('pending', 'requires_action', 'failed');
create index if not exists orders_easyparcel_booking_open_idx
  on public.orders (easyparcel_booking_state)
  where easyparcel_booking_state in ('booking', 'needs_attention');

-- One shop-wide reminder per account and day. Deliberately limited to the
-- 'ops-daily:' keys: order notifications lose their order_id when an order
-- is deleted (on delete set null) and must stay free to repeat.
create unique index if not exists notifications_ops_daily_user_key_uidx
  on public.notifications (user_id, key)
  where order_id is null and key like 'ops-daily:%';

-- ---------------------------------------------------------------------
-- 3. The rules, in one place. One row per open problem.
--      condition   payment_not_confirmed | refund_problem |
--                  courier_needs_attention | reconcile_failing |
--                  easyparcel_disconnected | reconcile_unobservable
--      order_id    null for the shop-wide conditions
--      dedup_key   notifications.key
--      since       when it became a problem
--    reconcile_unobservable is never announced: it only says the pg_net
--    response table could not be read, so admin_ops_health() can answer
--    "unknown" instead of "fine".
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
         format('The EasyParcel booking for order #%s did not complete. Open the order to check and finish it.',
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

-- ---------------------------------------------------------------------
-- 4. The job: write the notifications. Returns how many rows it wrote.
--    Recipients are every staff and owner profile, whatever their push
--    setting (same as send-order-notification: the inbox is not optional).
-- ---------------------------------------------------------------------
create or replace function public.ops_monitor_run()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_written integer;
begin
  delete from public.ops_cron_http_calls
   where requested_at < now() - interval '7 days';

  -- One statement: the rules are evaluated once and both inserts use that
  -- one answer.
  with batch as materialized (
    select f.order_id, f.dedup_key, f.title, f.body
      from public.ops_monitor_findings() f
     where f.condition <> 'reconcile_unobservable'
       and f.since > now() - interval '7 days'
  ),
  recipients as materialized (
    select p.id from public.profiles p where p.role in ('staff', 'owner')
  ),
  order_rows as (
    insert into public.notifications (user_id, title, body, order_id, type, key)
    select r.id, b.title, b.body, b.order_id, 'admin_alert', b.dedup_key
      from batch b cross join recipients r
     where b.order_id is not null
    on conflict (order_id, user_id, key) do nothing
    returning 1
  ),
  shop_rows as (
    insert into public.notifications (user_id, title, body, order_id, type, key)
    select r.id, b.title, b.body, null, 'admin_alert', b.dedup_key
      from batch b cross join recipients r
     where b.order_id is null
    on conflict (user_id, key) where order_id is null and key like 'ops-daily:%' do nothing
    returning 1
  )
  select (select count(*) from order_rows) + (select count(*) from shop_rows)
    into v_written;
  return v_written;
end;
$$;

-- Server only: cron runs them as the database owner.
revoke all on function public.ops_monitor_findings() from public, anon, authenticated;
grant execute on function public.ops_monitor_findings() to service_role;
revoke all on function public.ops_monitor_run() from public, anon, authenticated;
grant execute on function public.ops_monitor_run() to service_role;

-- ---------------------------------------------------------------------
-- 5. Dashboard health line (same pattern as admin_order_summary, 0074).
--    One row. The three counts are orders with that problem open now, of
--    any age. reconcile_failing is null when the pg_net response table
--    could not be read (unknown, not fine).
-- ---------------------------------------------------------------------
create or replace function public.admin_ops_health()
returns table (
  payment_not_confirmed bigint,
  refund_problems bigint,
  courier_needs_attention bigint,
  reconcile_failing boolean,
  easyparcel_disconnected boolean,
  total_problems bigint,
  checked_at timestamptz
)
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
  with f as (select * from public.ops_monitor_findings()),
  c as (
    select count(distinct f.order_id) filter (where f.condition = 'payment_not_confirmed') as payments,
           count(distinct f.order_id) filter (where f.condition = 'refund_problem') as refunds,
           count(distinct f.order_id) filter (where f.condition = 'courier_needs_attention') as couriers,
           case when bool_or(f.condition = 'reconcile_unobservable') then null
                else coalesce(bool_or(f.condition = 'reconcile_failing'), false)
           end as reconcile,
           coalesce(bool_or(f.condition = 'easyparcel_disconnected'), false) as easyparcel
      from f
  )
  select c.payments, c.refunds, c.couriers, c.reconcile, c.easyparcel,
         c.payments + c.refunds + c.couriers
           + (coalesce(c.reconcile, false))::int + (c.easyparcel)::int,
         now()
    from c;
end;
$$;

revoke all on function public.admin_ops_health() from public, anon;
grant execute on function public.admin_ops_health() to authenticated;

-- ---------------------------------------------------------------------
-- 6. Schedule. Unschedule first so re-running this file never leaves two
--    jobs (same as 0014 and 0049).
-- ---------------------------------------------------------------------
select cron.unschedule(jobid)
  from cron.job
 where jobname = 'ops-monitor';

select cron.schedule(
  'ops-monitor',
  '*/15 * * * *', -- every 15 minutes
  $$select public.ops_monitor_run();$$
);

commit;
