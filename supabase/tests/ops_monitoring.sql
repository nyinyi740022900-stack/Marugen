-- Disposable database only. Checks migration 0080 against the full schema.
-- All fixtures are synthetic and rolled back.
\set ON_ERROR_STOP on
begin;

create schema ops_test;
create function ops_test.fail_unless(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', message; end if;
end $$;
-- Runs a statement as the current role and reports how it ended:
-- 'ok', 'denied' (no privilege / RLS), or 'rejected: <message>'.
create function ops_test.attempt(statement text) returns text
language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception
  when insufficient_privilege then return 'denied';
  when others then return 'rejected: ' || sqlerrm;
end $$;
grant usage on schema ops_test to anon, authenticated, service_role;

-- Order n (1..99), created `age` ago, left pending or moved to paid.
create function ops_test.order_id(n int) returns uuid language sql immutable as $$
  select ('80200000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid;
$$;
create function ops_test.new_order(n int, state text, intent text, age interval) returns void
language plpgsql as $$
begin
  insert into public.orders (id, user_id, status, total, stripe_payment_intent_id, created_at)
  values (ops_test.order_id(n), '80000000-0000-0000-0000-000000000001', 'pending', 100, intent, now() - age);
  if state <> 'pending' then
    update public.orders set status = state where id = ops_test.order_id(n);
  end if;
end $$;
-- Monitoring notifications about order n, and the accounts that got them.
create function ops_test.alerts(n int) returns bigint language sql as $$
  select count(*) from public.notifications
   where order_id = ops_test.order_id(n) and key like 'ops:%';
$$;
create function ops_test.alerted_once(n int) returns boolean language sql as $$
  select count(*) = 2
     and count(*) filter (where user_id = '80000000-0000-0000-0000-000000000002') = 1
     and count(*) filter (where user_id = '80000000-0000-0000-0000-000000000004') = 1
     and bool_and(type = 'admin_alert')
    from public.notifications
   where order_id = ops_test.order_id(n) and key like 'ops:%';
$$;
-- admin_ops_health() as seen by the staff account.
create function ops_test.health() returns record language plpgsql as $$
declare h record;
begin
  perform set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', true);
  select * into h from public.admin_ops_health();
  perform set_config('request.jwt.claim.sub', '', true);
  return h;
end $$;
create function ops_test.reconcile_failing() returns boolean language sql as $$
  select h.reconcile_failing from ops_test.health() as h(
    payment_not_confirmed bigint, refund_problems bigint, courier_needs_attention bigint,
    reconcile_failing boolean, easyparcel_disconnected boolean, total_problems bigint,
    checked_at timestamptz);
$$;
-- Four reconcile calls 5, 10, 15 and 20 minutes ago, all answered `status`
-- (null: timed out).
create function ops_test.reconcile_calls(status integer) returns void language plpgsql as $$
begin
  delete from public.ops_cron_http_calls;
  delete from net._http_response;
  insert into public.ops_cron_http_calls (request_id, job, requested_at)
  select 9000 + m, 'reconcile-pending-orders', now() - make_interval(mins => m)
    from unnest(array[5, 10, 15, 20]) m;
  insert into net._http_response (id, status_code, timed_out, error_msg)
  select 9000 + m, status, status is null,
         case when status is null then 'Timeout was reached' end
    from unnest(array[5, 10, 15, 20]) m;
end $$;

-- =====================================================================
-- Fixtures
-- =====================================================================
insert into auth.users (id, email) values
  ('80000000-0000-0000-0000-000000000001', 'buyer@example.invalid'),
  ('80000000-0000-0000-0000-000000000002', 'staff@example.invalid'),
  ('80000000-0000-0000-0000-000000000004', 'owner@example.invalid'),
  ('80000000-0000-0000-0000-000000000005', 'customer-two@example.invalid');
update public.profiles set role = 'staff' where id = '80000000-0000-0000-0000-000000000002';
update public.profiles set role = 'owner' where id = '80000000-0000-0000-0000-000000000004';
-- A configured shop: the reconcile job is scheduled (0049) and has its secrets.
insert into vault.decrypted_secrets (name, decrypted_secret) values
  ('service_role_key', 'local-test-key'), ('project_url', 'http://localhost.invalid');

-- =====================================================================
-- 1. Objects and privileges
-- =====================================================================
select ops_test.fail_unless(
  (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
     from pg_proc p where p.oid = fn::regprocedure),
  format('%s is SECURITY DEFINER with a pinned search_path', fn))
  from unnest(array['public.ops_monitor_run()', 'public.ops_monitor_findings()',
                    'public.admin_ops_health()']) fn;
select ops_test.fail_unless(
  not has_function_privilege(r, fn, 'execute'),
  format('%s cannot execute %s', r, fn))
  from unnest(array['anon', 'authenticated']) r,
       unnest(array['public.ops_monitor_run()', 'public.ops_monitor_findings()',
                    'public.reconcile_pending_orders()']) fn;
select ops_test.fail_unless(
  has_function_privilege('service_role', fn, 'execute'),
  format('service_role can execute %s', fn))
  from unnest(array['public.ops_monitor_run()', 'public.ops_monitor_findings()',
                    'public.reconcile_pending_orders()']) fn;
select ops_test.fail_unless(
  not has_function_privilege('anon', 'public.admin_ops_health()', 'execute')
  and has_function_privilege('authenticated', 'public.admin_ops_health()', 'execute'),
  'admin_ops_health is for signed-in users only');
select ops_test.fail_unless(
  (select relrowsecurity from pg_class where oid = 'public.ops_cron_http_calls'::regclass)
  and not exists (select 1 from pg_policies where tablename = 'ops_cron_http_calls')
  and not has_table_privilege('anon', 'public.ops_cron_http_calls', 'select')
  and not has_table_privilege('authenticated', 'public.ops_cron_http_calls', 'select'),
  'ops_cron_http_calls is closed to the API roles');
select ops_test.fail_unless(
  (select count(*) = 1 and min(schedule) = '*/15 * * * *'
      and min(command) = 'select public.ops_monitor_run();'
     from cron.job where jobname = 'ops-monitor'),
  'exactly one ops-monitor job every 15 minutes after applying 0080 twice');
select ops_test.fail_unless(
  (select count(*) = 1 from cron.job where jobname = 'reconcile-pending-orders'),
  'the reconcile job is still scheduled exactly once');

-- Real calls: anon and every signed-in account are refused the job.
set local role anon;
select ops_test.fail_unless(
  ops_test.attempt(format('select %s', fn)) = 'denied',
  format('anon cannot call %s', fn))
  from unnest(array['public.ops_monitor_run()', 'count(*) from public.ops_monitor_findings()',
                    'count(*) from public.admin_ops_health()',
                    'count(*) from public.ops_cron_http_calls']) fn;
reset role;
select set_config('request.jwt.claim.sub', u, true),
       set_config('role', 'authenticated', true),
       ops_test.fail_unless(
         ops_test.attempt(format('select %s', fn)) = 'denied',
         format('signed-in user %s cannot call %s', u, fn))
  from unnest(array[
    '80000000-0000-0000-0000-000000000001',
    '80000000-0000-0000-0000-000000000002',
    '80000000-0000-0000-0000-000000000004']) u,
       unnest(array['public.ops_monitor_run()', 'count(*) from public.ops_monitor_findings()',
                    'count(*) from public.ops_cron_http_calls']) fn;
-- The health RPC: customers are turned away, staff and owner get one row.
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true),
       ops_test.fail_unless(
         ops_test.attempt('select count(*) from public.admin_ops_health()') = 'denied',
         'a customer calling admin_ops_health is refused');
select set_config('request.jwt.claim.sub', u, true),
       ops_test.fail_unless(
         (select count(*) = 1 and bool_and(total_problems = 0 and reconcile_failing is false
                                           and easyparcel_disconnected is false
                                           and checked_at is not null)
            from public.admin_ops_health()),
         format('admin %s gets one all-clear health row on a quiet shop', u))
  from unnest(array['80000000-0000-0000-0000-000000000002',
                    '80000000-0000-0000-0000-000000000004']) u;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- A quiet shop: nothing to say.
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'a quiet shop writes no notification');
select ops_test.fail_unless(
  not exists (select 1 from public.notifications), 'the inbox is still empty');

-- =====================================================================
-- 2. Fixtures for every order condition, on both sides of each window
-- =====================================================================
-- Payment not confirmed: pending + PaymentIntent, 45 minutes.
select ops_test.new_order(1, 'pending', 'pi_ops_01', interval '46 minutes');
select ops_test.new_order(2, 'pending', 'pi_ops_02', interval '44 minutes');
select ops_test.new_order(3, 'pending', null, interval '3 hours');        -- no PaymentIntent
select ops_test.new_order(4, 'pending', '  ', interval '3 hours');        -- blank PaymentIntent
select ops_test.new_order(5, 'paid', 'pi_ops_05', interval '3 hours');    -- settled
select ops_test.new_order(6, 'pending', 'pi_ops_06', interval '8 days');  -- too old to announce

-- Refunds, recorded the way stripe-refund / stripe-webhook record them.
select ops_test.new_order(n, 'paid', 'pi_ops_' || n, interval '2 days') from generate_series(11, 16) n;
set local role service_role;
select public.record_verified_refund(ops_test.order_id(11), 'pi_ops_11', 're_ops_11', 5000, 'sgd',
  'failed', now() - interval '10 minutes', 'insufficient_funds', now() - interval '10 minutes');
select public.record_verified_refund(ops_test.order_id(12), 'pi_ops_12', 're_ops_12', 5000, 'sgd',
  'requires_action', now() - interval '10 minutes', null, now() - interval '10 minutes');
select public.record_verified_refund(ops_test.order_id(13), 'pi_ops_13', 're_ops_13', 5000, 'sgd',
  'pending', now() - interval '25 hours', null, now() - interval '25 hours');
select public.record_verified_refund(ops_test.order_id(14), 'pi_ops_14', 're_ops_14', 5000, 'sgd',
  'pending', now() - interval '23 hours', null, now() - interval '23 hours');
select public.record_verified_refund(ops_test.order_id(15), 'pi_ops_15', 're_ops_15', 10000, 'sgd',
  'succeeded', now() - interval '25 hours', null, now() - interval '25 hours');
select public.record_verified_refund(ops_test.order_id(16), 'pi_ops_16', 're_ops_16', 5000, 'sgd',
  'succeeded', now() - interval '25 hours', null, now() - interval '25 hours');
reset role;
select ops_test.fail_unless(
  (select array_agg(refund_status order by id) from public.orders
    where id in (select ops_test.order_id(n) from generate_series(11, 16) n))
  = array['failed', 'requires_action', 'pending', 'pending', 'succeeded', 'partially_refunded'],
  'refund fixtures carry the statuses the payment backend writes');

-- Courier bookings, 30 minutes.
select ops_test.new_order(n, 'paid', 'pi_ops_' || n, interval '1 day') from generate_series(21, 27) n;
update public.orders set fulfillment_method = 'courier', tracking_provider = 'easyparcel',
       tracking_registered = true
 where id in (select ops_test.order_id(n) from generate_series(21, 24) n);
update public.orders set easyparcel_booking_state = 'needs_attention',
       easyparcel_booking_started_at = now() - interval '31 minutes' where id = ops_test.order_id(21);
update public.orders set easyparcel_booking_state = 'needs_attention',
       easyparcel_booking_started_at = now() - interval '29 minutes' where id = ops_test.order_id(22);
update public.orders set easyparcel_booking_state = 'booked', qxpress_tracking_no = 'OPS-AWB-23',
       easyparcel_booking_started_at = now() - interval '3 hours' where id = ops_test.order_id(23);
-- Claimed, then the booking function died: never left `booking`.
update public.orders set easyparcel_booking_state = 'booking',
       easyparcel_booking_started_at = now() - interval '31 minutes' where id = ops_test.order_id(24);
-- Split orders: one box failed 40 minutes ago / 10 minutes ago / all booked.
insert into public.order_parcels
  (order_id, parcel_number, items, weight_kg, length_cm, width_cm, height_cm,
   collection_date, state, tracking_updated_at)
values
  (ops_test.order_id(25), 1, '[{"n":1}]', 1, 10, 10, 10, current_date + 1, 'booked', now() - interval '40 minutes'),
  (ops_test.order_id(25), 2, '[{"n":1}]', 1, 10, 10, 10, current_date + 1, 'needs_attention', now() - interval '40 minutes'),
  (ops_test.order_id(26), 1, '[{"n":1}]', 1, 10, 10, 10, current_date + 1, 'payment_required', now() - interval '10 minutes'),
  (ops_test.order_id(27), 1, '[{"n":1}]', 1, 10, 10, 10, current_date + 1, 'booked', now() - interval '40 minutes');

-- =====================================================================
-- 3. One run: each problem once, to staff and owner only
-- =====================================================================
-- 1 + 3 refunds + 3 couriers = 7 orders, two admin accounts each.
select ops_test.fail_unless(public.ops_monitor_run() = 14, 'the first run writes 14 notifications');
select ops_test.fail_unless(ops_test.alerted_once(n), format('order %s: one alert each for staff and owner', n))
  from unnest(array[1, 11, 12, 13, 21, 24, 25]) n;
select ops_test.fail_unless(ops_test.alerts(n) = 0, format('order %s is inside its window or fine: no alert', n))
  from unnest(array[2, 3, 4, 5, 14, 15, 16, 22, 23, 26, 27]) n;
select ops_test.fail_unless(ops_test.alerts(6) = 0, 'a problem older than 7 days is not announced');
select ops_test.fail_unless(
  (select count(*) = 14 from public.notifications),
  'nothing else was written');
select ops_test.fail_unless(
  not exists (select 1 from public.notifications n join public.profiles p on p.id = n.user_id
               where p.role = 'customer'),
  'no customer received a monitoring notification');
select ops_test.fail_unless(
  (select array_agg(distinct title order by title) from public.notifications)
  = array['Courier booking needs attention', 'Payment not confirmed', 'Refund failed',
          'Refund needs action', 'Refund still pending'],
  'each condition has its own title');
select ops_test.fail_unless(
  (select bool_and(n.body like '%#' || o.order_number || '%' and n.read is false and n.dismissed_at is null)
     from public.notifications n join public.orders o on o.id = n.order_id),
  'every alert names its order and arrives unread');
-- The customer whose order is stuck sees nothing of it through RLS.
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true),
       set_config('role', 'authenticated', true);
select ops_test.fail_unless(
  (select count(*) = 0 from public.notifications), 'the buyer cannot read any monitoring notification');
reset role;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', true),
       set_config('role', 'authenticated', true);
select ops_test.fail_unless(
  (select count(*) = 7 from public.notifications), 'staff read their own seven');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Health counts every open problem, the 8-day-old one included.
select ops_test.fail_unless(
  (select h.payment_not_confirmed = 2 and h.refund_problems = 3 and h.courier_needs_attention = 3
      and h.reconcile_failing is false and h.easyparcel_disconnected is false
      and h.total_problems = 8
     from ops_test.health() as h(
       payment_not_confirmed bigint, refund_problems bigint, courier_needs_attention bigint,
       reconcile_failing boolean, easyparcel_disconnected boolean, total_problems bigint,
       checked_at timestamptz)),
  'admin_ops_health counts 2 payments, 3 refunds, 3 courier bookings');

-- Once and only once: later runs, read and dismissed rows change nothing.
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'a second run writes nothing');
update public.notifications set read = true, dismissed_at = now()
 where user_id = '80000000-0000-0000-0000-000000000002';
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'dismissed alerts are not sent again');
select ops_test.fail_unless(
  (select count(*) = 14 from public.notifications), 'still 14 notifications');

-- =====================================================================
-- 4. Windows, repeats and recovery
-- =====================================================================
-- Order 2 crosses 45 minutes; order 22 and the box of order 26 cross 30.
update public.orders set created_at = now() - interval '46 minutes' where id = ops_test.order_id(2);
update public.orders set easyparcel_booking_started_at = now() - interval '31 minutes'
 where id = ops_test.order_id(22);
update public.order_parcels set tracking_updated_at = now() - interval '31 minutes'
 where order_id = ops_test.order_id(26);
-- Order 14's refund crosses 24 hours.
update public.payment_refunds set stripe_created_at = now() - interval '25 hours'
 where stripe_refund_id = 're_ops_14';
select ops_test.fail_unless(public.ops_monitor_run() = 8, 'four orders crossed their window: 8 notifications');
select ops_test.fail_unless(ops_test.alerted_once(n), format('order %s alerted once after its window', n))
  from unnest(array[2, 22, 26, 14]) n;

-- A second refund attempt on order 11 fails too: that is news.
set local role service_role;
select public.record_verified_refund(ops_test.order_id(11), 'pi_ops_11', 're_ops_11b', 5000, 'sgd',
  'failed', now() - interval '1 minute', 'declined', now());
reset role;
select ops_test.fail_unless(public.ops_monitor_run() = 2, 'a second failed refund is announced');
select ops_test.fail_unless(ops_test.alerts(11) = 4, 'order 11 now has one alert per failed refund and admin');
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'and only once');

-- Problems that go away leave the health line, and are not re-sent.
update public.orders set status = 'paid' where id = ops_test.order_id(1);
set local role service_role;
select public.record_verified_refund(ops_test.order_id(13), 'pi_ops_13', 're_ops_13', 5000, 'sgd',
  'succeeded', now() - interval '25 hours', null, now());
reset role;
update public.orders set easyparcel_booking_state = 'booked', qxpress_tracking_no = 'OPS-AWB-21'
 where id = ops_test.order_id(21);
select ops_test.fail_unless(
  (select h.payment_not_confirmed = 2 and h.refund_problems = 3 and h.courier_needs_attention = 4
     from ops_test.health() as h(
       payment_not_confirmed bigint, refund_problems bigint, courier_needs_attention bigint,
       reconcile_failing boolean, easyparcel_disconnected boolean, total_problems bigint,
       checked_at timestamptz)),
  'health follows the data: orders 1, 13 and 21 are resolved, 2, 14, 22 and 26 are open');
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'resolved problems write nothing');

-- A new staff account is told about what is still open, once.
insert into auth.users (id, email) values
  ('80000000-0000-0000-0000-000000000006', 'new-staff@example.invalid');
update public.profiles set role = 'staff' where id = '80000000-0000-0000-0000-000000000006';
select ops_test.fail_unless(
  public.ops_monitor_run() = 8, 'a new staff account gets the 8 problems that are still open and recent');
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'and only once');
delete from auth.users where id = '80000000-0000-0000-0000-000000000006';

-- =====================================================================
-- 5. EasyParcel connection (daily reminder)
-- =====================================================================
insert into public.easyparcel_connection
  (id, access_token, refresh_token, access_token_expires_at, refresh_token_expires_at)
values (1, 'access-test', 'refresh-test', now() - interval '1 hour', now() + interval '1 day');
select ops_test.fail_unless(
  public.ops_monitor_run() = 0, 'an expired access token with a live refresh token is normal');
update public.easyparcel_connection set refresh_token_expires_at = now() - interval '1 hour';
select ops_test.fail_unless(public.ops_monitor_run() = 2, 'an expired refresh token alerts staff and owner');
select ops_test.fail_unless(
  (select count(*) = 2 and count(distinct user_id) = 2 and bool_and(order_id is null)
      and bool_and(type = 'admin_alert' and title = 'EasyParcel disconnected')
      and bool_and(key = 'ops-daily:easyparcel_disconnected:'
                         || to_char(now() at time zone 'Asia/Singapore', 'YYYY-MM-DD'))
     from public.notifications where key like 'ops-daily:easyparcel%'),
  'the reminder is keyed by the Singapore date and has no order');
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'not again on the same day');
-- The unique index is what holds, even against a direct second insert.
select ops_test.fail_unless(
  ops_test.attempt($q$
    insert into public.notifications (user_id, title, body, type, key)
    select user_id, title, body, type, key from public.notifications
     where key like 'ops-daily:easyparcel%' limit 1$q$) like 'rejected:%notifications_ops_daily_user_key_uidx%',
  'a second reminder for the same account and day is refused by the index');
-- Yesterday's reminder does not stop today's.
update public.notifications set key = 'ops-daily:easyparcel_disconnected:2000-01-01'
 where key like 'ops-daily:easyparcel%';
select ops_test.fail_unless(public.ops_monitor_run() = 2, 'a new day brings one new reminder');
-- After a week of reminders it stops, but the health line still says so.
update public.notifications set key = 'ops-daily:easyparcel_disconnected:2000-01-02'
 where key like 'ops-daily:easyparcel%' and key not like '%2000-01-01';
update public.easyparcel_connection set refresh_token_expires_at = now() - interval '8 days';
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'no reminder once it has been down for over 7 days');
select ops_test.fail_unless(
  (select h.easyparcel_disconnected
     from ops_test.health() as h(
       payment_not_confirmed bigint, refund_problems bigint, courier_needs_attention bigint,
       reconcile_failing boolean, easyparcel_disconnected boolean, total_problems bigint,
       checked_at timestamptz)),
  'health still reports EasyParcel as disconnected');
update public.easyparcel_connection set refresh_token_expires_at = now() + interval '30 days';

-- =====================================================================
-- 6. Reconcile cron job
-- =====================================================================
-- The job records the pg_net request id of each call it makes.
set local role service_role;
select public.reconcile_pending_orders();
select public.reconcile_pending_orders();
reset role;
select ops_test.fail_unless(
  (select count(*) = 2 and count(distinct request_id) = 2
      and bool_and(job = 'reconcile-pending-orders')
     from public.ops_cron_http_calls),
  'reconcile_pending_orders records one request id per call');
-- Too recent to judge: no answer yet is not a failure.
select ops_test.fail_unless(
  ops_test.reconcile_failing() is false, 'calls under 2 minutes old are not judged');

select ops_test.reconcile_calls(200);
select ops_test.fail_unless(ops_test.reconcile_failing() is false, 'four 200 answers: healthy');
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'a healthy job writes nothing');
select ops_test.reconcile_calls(500);
update net._http_response set status_code = 200 where id = 9020;
select ops_test.fail_unless(
  ops_test.reconcile_failing() is false, 'one 2xx among the failures: not (yet) failing');
select ops_test.reconcile_calls(500);
delete from public.ops_cron_http_calls where request_id in (9015, 9020);
select ops_test.fail_unless(
  ops_test.reconcile_failing() is false, 'two failed calls are not enough to alert');
select ops_test.reconcile_calls(null);
select ops_test.fail_unless(ops_test.reconcile_failing(), 'four timeouts: failing');
delete from net._http_response;
select ops_test.fail_unless(ops_test.reconcile_failing(), 'four calls never answered: failing');
select ops_test.reconcile_calls(403);
select ops_test.fail_unless(ops_test.reconcile_failing(), 'four 403 answers: failing');
-- Answers to other pg_net requests are not mistaken for the job's.
insert into net._http_response (id, status_code) values (1, 200), (2, 200), (3, 200);
select ops_test.fail_unless(ops_test.reconcile_failing(), 'a 200 for someone else''s request does not count');

select ops_test.fail_unless(public.ops_monitor_run() = 2, 'a failing job alerts staff and owner');
select ops_test.fail_unless(
  (select count(*) = 2 and count(distinct user_id) = 2 and bool_and(order_id is null)
      and bool_and(title = 'Payment check not running' and type = 'admin_alert')
      and bool_and(key = 'ops-daily:reconcile_failing:'
                         || to_char(now() at time zone 'Asia/Singapore', 'YYYY-MM-DD'))
     from public.notifications where key like 'ops-daily:reconcile%'),
  'the reminder is keyed by the Singapore date and has no order');
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'not again on the same day');

-- Missing Vault secret: the job silently does nothing, which is a failure.
select ops_test.reconcile_calls(200);
delete from vault.decrypted_secrets where name = 'project_url';
select ops_test.fail_unless(ops_test.reconcile_failing(), 'a missing Vault secret: failing');
insert into vault.decrypted_secrets (name, decrypted_secret) values ('project_url', 'http://localhost.invalid');
select ops_test.fail_unless(ops_test.reconcile_failing() is false, 'secrets back: healthy');
-- Job not scheduled.
create temporary table ops_saved_job on commit drop as
  select * from cron.job where jobname = 'reconcile-pending-orders';
delete from cron.job where jobname = 'reconcile-pending-orders';
select ops_test.fail_unless(ops_test.reconcile_failing(), 'an unscheduled job: failing');
insert into cron.job select * from ops_saved_job;
select ops_test.fail_unless(ops_test.reconcile_failing() is false, 'job back: healthy');

-- Old request ids are pruned by the run.
insert into public.ops_cron_http_calls (request_id, job, requested_at)
values (1, 'reconcile-pending-orders', now() - interval '8 days');
select ops_test.fail_unless(public.ops_monitor_run() = 0, 'healthy again: nothing written');
select ops_test.fail_unless(
  not exists (select 1 from public.ops_cron_http_calls where request_id = 1),
  'request ids older than 7 days are pruned');

-- pg_net's table unreadable: say "unknown", and keep watching the rest.
select ops_test.new_order(31, 'pending', 'pi_ops_31', interval '50 minutes');
alter table net._http_response rename to _http_response_gone;
set local client_min_messages = error;
select ops_test.fail_unless(
  ops_test.reconcile_failing() is null, 'health says unknown (null) when pg_net cannot be read');
select ops_test.fail_unless(
  public.ops_monitor_run() = 2 and ops_test.alerted_once(31),
  'the other conditions still alert when pg_net cannot be read');
reset client_min_messages;
alter table net._http_response_gone rename to _http_response;

-- =====================================================================
-- 7. Nothing here gets in the way of deleting an order
-- =====================================================================
-- on delete set null leaves several (null, user, 'ops:...') rows per admin;
-- the daily index must not catch them.
select ops_test.fail_unless(
  ops_test.attempt($q$update public.notifications set order_id = null
                       where key = 'ops:payment_not_confirmed'$q$) = 'ok',
  'order alerts can lose their order');
select ops_test.fail_unless(
  (select count(*) = 3 from public.notifications
    where order_id is null and key = 'ops:payment_not_confirmed'
      and user_id = '80000000-0000-0000-0000-000000000004'),
  'the owner keeps all three orphaned payment alerts: they do not collide');

rollback;
