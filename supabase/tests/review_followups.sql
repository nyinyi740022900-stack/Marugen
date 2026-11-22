-- Disposable database only. Checks migration 0081 against the full schema.
-- All fixtures are synthetic and rolled back.
\set ON_ERROR_STOP on
begin;

create schema followup_test;
create function followup_test.fail_unless(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', message; end if;
end $$;
-- Runs a statement as the current role and reports how it ended:
-- 'ok', 'denied' (no privilege / RLS), or 'rejected: <sqlstate> <message>'.
create function followup_test.attempt(statement text) returns text
language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception
  when insufficient_privilege then return 'denied';
  when others then return 'rejected: ' || sqlstate || ' ' || sqlerrm;
end $$;
grant usage on schema followup_test to anon, authenticated, service_role;
create function followup_test.order_id(n int) returns uuid language sql immutable as $$
  select ('81200000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid;
$$;
create function followup_test.promo_id(n int) returns uuid language sql immutable as $$
  select ('81300000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid;
$$;
-- Become one signed-in account through the API role, or nobody again.
create function followup_test.sign_in(account uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(account::text, ''), true);
end $$;

-- =====================================================================
-- Fixtures
-- =====================================================================
insert into auth.users (id, email) values
  ('81000000-0000-0000-0000-000000000001', 'buyer@example.invalid'),
  ('81000000-0000-0000-0000-000000000002', 'staff@example.invalid'),
  ('81000000-0000-0000-0000-000000000004', 'owner@example.invalid'),
  ('81000000-0000-0000-0000-000000000005', 'leaving-buyer@example.invalid');
update public.profiles set role = 'staff' where id = '81000000-0000-0000-0000-000000000002';
update public.profiles set role = 'owner' where id = '81000000-0000-0000-0000-000000000004';

-- =====================================================================
-- 1. admin_payments_summary: the count covers only what the sum covers
-- =====================================================================
--   order  status     total  refunded      PaymentIntent  collected  counted
--   01     paid       50     -             yes            50         yes
--   02     cancelled  70     -             yes            0          no
--   03     pending    40     -             yes            0          no
--   04     refunded   80     80 succeeded  yes            0          no
--   05     refunded   60     20 failed     yes            40         yes
--   06     shipped    100    30 partial    yes            70         yes
--   07     delivered  25     -             no             -          no
--   08     paid       10     15 (over)     yes            0          yes
--   09     packing    30     -             yes            30         yes
--   10     paid       20     -             ''             -          no
--
--   5 paid orders, 190 collected. 0078 said 8 transactions.
insert into public.orders (id, user_id, status, total, stripe_payment_intent_id, created_at)
select followup_test.order_id(n), '81000000-0000-0000-0000-000000000001', 'pending', total, intent,
       now() - make_interval(days => 20 - n)
  from (values (1, 50, 'pi_fu_01'), (2, 70, 'pi_fu_02'), (3, 40, 'pi_fu_03'), (4, 80, 'pi_fu_04'),
               (5, 60, 'pi_fu_05'), (6, 100, 'pi_fu_06'), (7, 25, null), (8, 10, 'pi_fu_08'),
               (9, 30, 'pi_fu_09'), (10, 20, '')) v(n, total, intent);
update public.orders set status = 'cancelled' where id = followup_test.order_id(2);
update public.orders set status = 'paid'
 where id in (select followup_test.order_id(n) from unnest(array[1, 4, 5, 6, 7, 8, 9, 10]) n);
update public.orders set status = 'refunded', refund_amount = 80, refund_status = 'succeeded', refunded_at = now()
 where id = followup_test.order_id(4);
update public.orders set status = 'refunded', refund_amount = 20, refund_status = 'failed'
 where id = followup_test.order_id(5);
update public.orders set status = 'shipped', refund_amount = 30, refund_status = 'partially_refunded'
 where id = followup_test.order_id(6);
update public.orders set status = 'shipped' where id = followup_test.order_id(7);
update public.orders set status = 'delivered' where id = followup_test.order_id(7);
update public.orders set refund_amount = 15, refund_status = 'partially_refunded'
 where id = followup_test.order_id(8);
update public.orders set status = 'packing' where id = followup_test.order_id(9);
select followup_test.fail_unless(
  (select string_agg(status, ',' order by id) from public.orders
    where id in (select followup_test.order_id(n) from generate_series(1, 10) n))
    = 'paid,cancelled,pending,refunded,refunded,shipped,delivered,paid,packing,paid',
  'payments fixture orders reached their intended statuses');

-- The 0078 definition of the sum, written out again: the new function
-- must return the same amount.
create temporary table followup_expected on commit drop as
select count(*) as with_intent,
       coalesce(sum(
         case
           when o.status in ('paid', 'packing', 'shipped', 'delivered')
             or (o.status = 'refunded'
                 and o.refund_status is not null
                 and o.refund_status <> 'succeeded')
           then least(greatest(o.total - coalesce(o.refund_amount, 0), 0), o.total)
           else 0
         end
       ), 0) as collected
  from public.orders o
 where nullif(o.stripe_payment_intent_id, '') is not null;
grant select on followup_expected to authenticated;
select followup_test.fail_unless(
  (select with_intent = 8 and collected = 190 from followup_expected),
  'fixture: 8 orders have a PaymentIntent and the 0078 sum is 190');

select followup_test.fail_unless(
  (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
      and p.provolatile = 's'
      and pg_get_function_result(p.oid) = 'TABLE(transaction_count bigint, collected numeric)'
     from pg_proc p where p.oid = 'public.admin_payments_summary()'::regprocedure),
  'admin_payments_summary keeps its return columns, SECURITY DEFINER and search_path');
select followup_test.fail_unless(
  not has_function_privilege('anon', 'public.admin_payments_summary()', 'execute')
  and has_function_privilege('authenticated', 'public.admin_payments_summary()', 'execute'),
  'admin_payments_summary: anon cannot execute, authenticated can');

set local role anon;
select followup_test.fail_unless(
  followup_test.attempt('select * from public.admin_payments_summary()') = 'denied',
  'anon cannot read payments totals');
reset role;
select followup_test.sign_in('81000000-0000-0000-0000-000000000001');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt('select * from public.admin_payments_summary()') = 'denied',
  'a customer cannot read payments totals');
reset role;
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  (select transaction_count = 5 from public.admin_payments_summary()),
  format('staff: 5 orders are counted (paid, refund-failed, shipped, over-refunded paid, packing), got %s',
         (select transaction_count from public.admin_payments_summary())));
select followup_test.fail_unless(
  (select s.collected = e.collected and s.collected = 190
     from public.admin_payments_summary() s, followup_expected e),
  format('staff: the sum is unchanged at 190, got %s',
         (select collected from public.admin_payments_summary())));
reset role;
select followup_test.sign_in('81000000-0000-0000-0000-000000000004');
set local role authenticated;
select followup_test.fail_unless(
  (select transaction_count = 5 and collected = 190 from public.admin_payments_summary()),
  'owner reads the same 5 / 190');
reset role;
select followup_test.sign_in(null);

-- A cancelled or abandoned checkout never moves the count; a payment does.
update public.orders set status = 'cancelled' where id = followup_test.order_id(3);
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  (select transaction_count = 5 and collected = 190 from public.admin_payments_summary()),
  'cancelling a pending checkout changes nothing');
reset role;
insert into public.orders (id, user_id, status, total, stripe_payment_intent_id)
values (followup_test.order_id(11), '81000000-0000-0000-0000-000000000001', 'pending', 15, 'pi_fu_11');
update public.orders set status = 'paid' where id = followup_test.order_id(11);
set local role authenticated;
select followup_test.fail_unless(
  (select transaction_count = 6 and collected = 205 from public.admin_payments_summary()),
  'one more paid order: 6 / 205');
reset role;
-- A refund that Stripe confirmed takes the order out of both numbers.
update public.orders set status = 'refunded', refund_amount = 15, refund_status = 'succeeded', refunded_at = now()
 where id = followup_test.order_id(11);
set local role authenticated;
select followup_test.fail_unless(
  (select transaction_count = 5 and collected = 190 from public.admin_payments_summary()),
  'a confirmed full refund: back to 5 / 190');
reset role;
select followup_test.sign_in(null);

-- =====================================================================
-- 2. Ops alert copy
-- =====================================================================
insert into public.orders (id, user_id, status, total, stripe_payment_intent_id, created_at)
values (followup_test.order_id(21), '81000000-0000-0000-0000-000000000001', 'pending', 100, 'pi_fu_21', now() - interval '1 day'),
       (followup_test.order_id(22), '81000000-0000-0000-0000-000000000001', 'pending', 100, 'pi_fu_22', now() - interval '1 day');
update public.orders set status = 'paid'
 where id in (followup_test.order_id(21), followup_test.order_id(22));
update public.orders set fulfillment_method = 'courier', tracking_provider = 'easyparcel',
       tracking_registered = true, easyparcel_booking_state = 'needs_attention',
       easyparcel_booking_started_at = now() - interval '31 minutes'
 where id in (followup_test.order_id(21), followup_test.order_id(22));
-- Order 22 was announced to the staff account before 0081, with the old text.
insert into public.notifications (user_id, title, body, order_id, type, key)
select '81000000-0000-0000-0000-000000000002', 'Courier booking needs attention',
       format('The EasyParcel booking for order #%s did not complete. Open the order to check and finish it.',
              o.order_number),
       o.id, 'admin_alert', 'ops:courier_needs_attention'
  from public.orders o where o.id = followup_test.order_id(22);

select followup_test.fail_unless(
  (select count(*) = 2
      and bool_and(f.dedup_key = 'ops:courier_needs_attention')
      and bool_and(f.title = 'Courier booking needs attention')
      and bool_and(f.body = format(
            'The EasyParcel booking for order #%s did not complete. Open it in Orders › Fulfillment to finish it.',
            o.order_number))
     from public.ops_monitor_findings() f join public.orders o on o.id = f.order_id
    where f.condition = 'courier_needs_attention'),
  format('courier alert: same key and title, body points at Orders › Fulfillment, got %s',
         (select string_agg(f.body, ' | ') from public.ops_monitor_findings() f
           where f.condition = 'courier_needs_attention')));
select followup_test.fail_unless(
  not exists (select 1 from public.ops_monitor_findings() f
               where f.body ilike '%open the order%'),
  'no alert tells staff to open the order page');

-- 21: staff + owner. 22: owner only, the staff row already exists.
-- (The run also announces the failed refund of order 05 from section 1.)
select followup_test.fail_unless(public.ops_monitor_run() > 0, 'the monitor run wrote alerts');
select followup_test.fail_unless(
  (select count(*) = 4 from public.notifications
    where order_id in (followup_test.order_id(21), followup_test.order_id(22))),
  'an alert sent before 0081 is not sent again: 3 new courier rows, 4 in all');
select followup_test.fail_unless(
  (select count(*) = 1 and min(body) like '%Open the order to check and finish it.'
     from public.notifications
    where order_id = followup_test.order_id(22)
      and user_id = '81000000-0000-0000-0000-000000000002'),
  'the alert sent before 0081 is still the only one for that account and is untouched');
select followup_test.fail_unless(
  (select count(*) = 3
      and bool_and(n.type = 'admin_alert' and n.key = 'ops:courier_needs_attention')
      and bool_and(n.body like '%did not complete. Open it in Orders › Fulfillment to finish it.')
     from public.notifications n
    where n.order_id in (followup_test.order_id(21), followup_test.order_id(22))
      and n.body not like '%Open the order%'),
  'new courier alerts carry the new text');
select followup_test.fail_unless(public.ops_monitor_run() = 0, 'a second run writes nothing');

-- The other bodies are 0080's, word for word.
insert into public.orders (id, user_id, status, total, stripe_payment_intent_id, created_at)
values (followup_test.order_id(23), '81000000-0000-0000-0000-000000000001', 'pending', 100, 'pi_fu_23', now() - interval '46 minutes');
insert into public.easyparcel_connection
  (id, access_token, refresh_token, access_token_expires_at, refresh_token_expires_at)
select 1, 'access-test', 'refresh-test', now() - interval '2 hours', now() - interval '1 hour'
 where not exists (select 1 from public.easyparcel_connection where id = 1);
update public.easyparcel_connection set refresh_token_expires_at = now() - interval '1 hour' where id = 1;
select followup_test.fail_unless(
  (select body from public.ops_monitor_findings() where condition = 'payment_not_confirmed')
    = format('Order #%s has been waiting for payment for over 45 minutes. Check it in Stripe.',
             (select order_number from public.orders where id = followup_test.order_id(23))),
  'payment alert body is unchanged');
select followup_test.fail_unless(
  (select body from public.ops_monitor_findings() where condition = 'easyparcel_disconnected')
    = 'The EasyParcel connection has expired, so courier bookings will fail. Reconnect it in Settings.',
  'EasyParcel alert body is unchanged');
select followup_test.fail_unless(
  (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
     from pg_proc p where p.oid = 'public.ops_monitor_findings()'::regprocedure)
  and not has_function_privilege('anon', 'public.ops_monitor_findings()', 'execute')
  and not has_function_privilege('authenticated', 'public.ops_monitor_findings()', 'execute')
  and has_function_privilege('service_role', 'public.ops_monitor_findings()', 'execute'),
  'ops_monitor_findings is still SECURITY DEFINER and server only');
select followup_test.fail_unless(
  (select count(*) = 1 from cron.job where jobname = 'ops-monitor'),
  'the ops-monitor job is still scheduled exactly once');

-- =====================================================================
-- 3. Promo codes: turn off, do not delete
-- =====================================================================
--   01 USED81     redeemed by the buyer on a paid order
--   02 UNUSED81   never redeemed
--   03 FREED81    redeemed, then the order was cancelled (slot released)
--   04 LEAVER81   redeemed by a customer who then deletes their account
--   05 SERVICE81  redeemed; deleted by the service role
insert into public.promo_codes (id, code, discount_type, discount_value) values
  (followup_test.promo_id(1), 'USED81', 'fixed', 5),
  (followup_test.promo_id(2), 'UNUSED81', 'fixed', 5),
  (followup_test.promo_id(3), 'FREED81', 'fixed', 5),
  (followup_test.promo_id(4), 'LEAVER81', 'fixed', 5),
  (followup_test.promo_id(5), 'SERVICE81', 'fixed', 5);
insert into public.orders (id, user_id, status, total, promo_code, discount_amount)
values (followup_test.order_id(31), '81000000-0000-0000-0000-000000000001', 'pending', 45, 'USED81', 5),
       (followup_test.order_id(33), '81000000-0000-0000-0000-000000000001', 'pending', 45, 'FREED81', 5),
       (followup_test.order_id(34), '81000000-0000-0000-0000-000000000005', 'pending', 45, 'LEAVER81', 5),
       (followup_test.order_id(35), '81000000-0000-0000-0000-000000000001', 'pending', 45, 'SERVICE81', 5);
select followup_test.fail_unless(public.claim_promo_redemption(followup_test.promo_id(n)),
  format('fixture: promo %s slot claimed', n)) from unnest(array[1, 3, 4, 5]) n;
insert into public.promo_code_redemptions (promo_code_id, user_id, order_id) values
  (followup_test.promo_id(1), '81000000-0000-0000-0000-000000000001', followup_test.order_id(31)),
  (followup_test.promo_id(3), '81000000-0000-0000-0000-000000000001', followup_test.order_id(33)),
  (followup_test.promo_id(4), '81000000-0000-0000-0000-000000000005', followup_test.order_id(34)),
  (followup_test.promo_id(5), '81000000-0000-0000-0000-000000000001', followup_test.order_id(35));
update public.orders set status = 'paid'
 where id in (followup_test.order_id(31), followup_test.order_id(34), followup_test.order_id(35));

select followup_test.fail_unless(
  (select count(*) = 1 from pg_trigger t
    where t.tgrelid = 'public.promo_codes'::regclass and t.tgname = 'promo_codes_keep_redeemed'
      and not t.tgisinternal and t.tgenabled = 'O')
  and (select not p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
         from pg_proc p where p.oid = 'public.guard_redeemed_promo_code_delete()'::regprocedure),
  'exactly one delete guard on promo_codes after applying 0081 twice, INVOKER with a pinned search_path');

-- Staff and owner, through the API role and the real RLS policies.
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(1)))
    = 'rejected: 23503 This promo code has been used and cannot be deleted. Turn it off instead.',
  format('staff cannot delete a used promo code, got %s',
         followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(1)))));
-- One statement over several codes: all or nothing.
select followup_test.fail_unless(
  followup_test.attempt('delete from public.promo_codes where code in (''USED81'', ''UNUSED81'')')
    like 'rejected: 23503 %',
  'a delete that includes a used code is refused as a whole');
reset role;
select followup_test.sign_in('81000000-0000-0000-0000-000000000004');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(1)))
    = 'rejected: 23503 This promo code has been used and cannot be deleted. Turn it off instead.',
  'the owner cannot delete a used promo code either');
reset role;
select followup_test.fail_unless(
  (select count(*) = 5 from public.promo_codes where code like '%81')
  and (select count(*) = 4 from public.promo_code_redemptions r
        where r.promo_code_id in (select followup_test.promo_id(n) from generate_series(1, 5) n))
  and (select times_redeemed = 1 from public.promo_codes where id = followup_test.promo_id(1)),
  'the refused deletes removed no code and no redemption');

-- A customer never could (RLS): nothing happens, with or without the guard.
select followup_test.sign_in('81000000-0000-0000-0000-000000000001');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt('delete from public.promo_codes where code like ''%81''') = 'ok',
  'a customer delete matches no rows');
reset role;
select followup_test.fail_unless(
  (select count(*) = 5 from public.promo_codes where code like '%81'),
  'a customer deleted nothing');

-- Turning it off is allowed and makes the code unusable.
select followup_test.sign_in('81000000-0000-0000-0000-000000000001');
set local role authenticated;
select followup_test.fail_unless(
  (select count(*) = 1 and bool_and(already_redeemed) from public.check_promo_code('used81')),
  'before: the customer can look the used code up');
reset role;
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('update public.promo_codes set active = false where id = %L',
                               followup_test.promo_id(1))) = 'ok',
  'staff can turn a used promo code off');
reset role;
select followup_test.fail_unless(
  (select active is false and times_redeemed = 1 from public.promo_codes where id = followup_test.promo_id(1))
  and (select count(*) = 1 from public.promo_code_redemptions
        where promo_code_id = followup_test.promo_id(1)),
  'turned off: the code, its count and its redemption are all still there');
select followup_test.sign_in('81000000-0000-0000-0000-000000000005');
set local role authenticated;
select followup_test.fail_unless(
  (select count(*) = 0 from public.check_promo_code('USED81')),
  'turned off: check_promo_code returns nothing to a customer');
reset role;
set local role service_role;
select followup_test.fail_unless(
  (select count(*) = 1 and bool_and(active is false) from public.find_promo_code('USED81')),
  'turned off: create-payment-intent''s lookup sees active = false (it answers "Invalid promo code")');
reset role;

-- An unused code can still be deleted by staff.
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(2))) = 'ok',
  'staff can delete an unused promo code');
reset role;
select followup_test.fail_unless(
  not exists (select 1 from public.promo_codes where id = followup_test.promo_id(2)),
  'the unused promo code is gone');

-- Once the only order that used it is cancelled the redemption is released
-- (0015 / 0069), the code is unused again and can be deleted.
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(3)))
    like 'rejected: 23503 %',
  'a code held by a pending order cannot be deleted');
reset role;
update public.orders set status = 'cancelled' where id = followup_test.order_id(33);
select followup_test.fail_unless(
  not exists (select 1 from public.promo_code_redemptions where promo_code_id = followup_test.promo_id(3)),
  'fixture: cancelling the order released the redemption');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(3))) = 'ok',
  'after the release staff can delete that code');
reset role;
select followup_test.fail_unless(
  not exists (select 1 from public.promo_codes where id = followup_test.promo_id(3)),
  'the released promo code is gone');
select followup_test.sign_in(null);

-- Account deletion (delete-account removes the auth user; 0051 keeps the
-- redemption without the customer): unaffected, and the code stays guarded.
delete from auth.users where id = '81000000-0000-0000-0000-000000000005';
select followup_test.fail_unless(
  not exists (select 1 from public.profiles where id = '81000000-0000-0000-0000-000000000005')
  and (select count(*) = 1 and bool_and(user_id is null) from public.promo_code_redemptions
        where promo_code_id = followup_test.promo_id(4))
  and (select times_redeemed = 1 from public.promo_codes where id = followup_test.promo_id(4)),
  'account deletion still works and keeps the anonymised redemption');
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(4)))
    like 'rejected: 23503 %',
  'a code used by a deleted account is still protected');
reset role;
select followup_test.sign_in(null);

-- Deleting an order still removes its own redemption (not a promo delete).
set local role service_role;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.orders where id = %L', followup_test.order_id(34))) = 'ok',
  'the service role can still delete an order that used a promo code');
reset role;
select followup_test.fail_unless(
  not exists (select 1 from public.promo_code_redemptions where order_id = followup_test.order_id(34))
  and exists (select 1 from public.promo_codes where id = followup_test.promo_id(4)),
  'the order''s redemption went with it, the code stayed');

-- The service role (maintenance scripts, Edge Functions) is not restricted.
set local role service_role;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(5))) = 'ok',
  'the service role can delete a used promo code');
reset role;
select followup_test.fail_unless(
  not exists (select 1 from public.promo_codes where id = followup_test.promo_id(5))
  and not exists (select 1 from public.promo_code_redemptions where promo_code_id = followup_test.promo_id(5)),
  'the service-role delete cascaded as before');

-- ---------------------------------------------------------------------
-- 3b. The guard does not depend on what RLS lets the caller read
-- ---------------------------------------------------------------------
--   01 USED81      still redeemed (order 31)
--   06 SPARE81     never redeemed
--   07 SERVICE82   redeemed; deleted by the service role
--   08 OWNER82     redeemed; deleted by the database owner
insert into public.promo_codes (id, code, discount_type, discount_value) values
  (followup_test.promo_id(6), 'SPARE81', 'fixed', 5),
  (followup_test.promo_id(7), 'SERVICE82', 'fixed', 5),
  (followup_test.promo_id(8), 'OWNER82', 'fixed', 5);
insert into public.orders (id, user_id, status, total, promo_code, discount_amount)
values (followup_test.order_id(37), '81000000-0000-0000-0000-000000000001', 'pending', 45, 'SERVICE82', 5),
       (followup_test.order_id(38), '81000000-0000-0000-0000-000000000001', 'pending', 45, 'OWNER82', 5);
select followup_test.fail_unless(public.claim_promo_redemption(followup_test.promo_id(n)),
  format('fixture: promo %s slot claimed', n)) from unnest(array[7, 8]) n;
insert into public.promo_code_redemptions (promo_code_id, user_id, order_id) values
  (followup_test.promo_id(7), '81000000-0000-0000-0000-000000000001', followup_test.order_id(37)),
  (followup_test.promo_id(8), '81000000-0000-0000-0000-000000000001', followup_test.order_id(38));
update public.orders set status = 'paid'
 where id in (followup_test.order_id(37), followup_test.order_id(38));

-- The helper: SECURITY DEFINER, pinned search_path, stable, and only the
-- signed-in API role may call it.
select followup_test.fail_unless(
  (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
      and p.provolatile = 's' and p.prorettype = 'boolean'::regtype
     from pg_proc p where p.oid = 'public.promo_code_has_redemptions(uuid)'::regprocedure)
  and (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'promo_code_has_redemptions'),
  'promo_code_has_redemptions is one stable SECURITY DEFINER function with a pinned search_path');
select followup_test.fail_unless(
  not has_function_privilege('public', 'public.promo_code_has_redemptions(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.promo_code_has_redemptions(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.promo_code_has_redemptions(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.promo_code_has_redemptions(uuid)', 'execute'),
  'promo_code_has_redemptions: only authenticated can execute');

-- Nobody but staff / owner gets an answer, and the non-answer is the same
-- for a used, an unused and a non-existent code.
set local role anon;
select followup_test.fail_unless(
  followup_test.attempt(format('select public.promo_code_has_redemptions(%L)', followup_test.promo_id(1))) = 'denied'
  and followup_test.attempt(format('select public.promo_code_has_redemptions(%L)', followup_test.promo_id(6))) = 'denied',
  'anon cannot call the helper');
reset role;
select followup_test.sign_in('81000000-0000-0000-0000-000000000001');
set local role authenticated;
select followup_test.fail_unless(
  public.promo_code_has_redemptions(followup_test.promo_id(1)) is null
  and public.promo_code_has_redemptions(followup_test.promo_id(6)) is null
  and public.promo_code_has_redemptions(followup_test.promo_id(99)) is null,
  'a customer learns nothing from the helper: null for used, unused and unknown codes');
reset role;
-- Signed in to nothing (a token without a profile).
select followup_test.sign_in(null);
set local role authenticated;
select followup_test.fail_unless(
  public.promo_code_has_redemptions(followup_test.promo_id(1)) is null
  and public.promo_code_has_redemptions(followup_test.promo_id(6)) is null,
  'an authenticated caller without an account learns nothing either');
reset role;
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  public.promo_code_has_redemptions(followup_test.promo_id(1)) is true
  and public.promo_code_has_redemptions(followup_test.promo_id(6)) is false
  and public.promo_code_has_redemptions(followup_test.promo_id(99)) is false,
  'staff get the real answer');
reset role;

-- Now take away what the old guard relied on: the staff SELECT policy.
savepoint without_redemptions_policy;
drop policy "Admins can view promo redemptions" on public.promo_code_redemptions;
set local role authenticated;
select followup_test.fail_unless(
  (select count(*) = 0 from public.promo_code_redemptions),
  'fixture: without the policy staff can read no redemption at all');
select followup_test.fail_unless(
  public.promo_code_has_redemptions(followup_test.promo_id(1)) is true
  and public.promo_code_has_redemptions(followup_test.promo_id(6)) is false,
  'without the policy the helper still answers staff correctly');
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(1)))
    = 'rejected: 23503 This promo code has been used and cannot be deleted. Turn it off instead.',
  format('without the policy staff still cannot delete a used promo code, got %s',
         followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(1)))));
select followup_test.fail_unless(
  followup_test.attempt('delete from public.promo_codes where code in (''USED81'', ''SPARE81'')')
    like 'rejected: 23503 %',
  'without the policy a delete that includes a used code is still refused as a whole');
reset role;
select followup_test.sign_in('81000000-0000-0000-0000-000000000004');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(1)))
    = 'rejected: 23503 This promo code has been used and cannot be deleted. Turn it off instead.',
  'without the policy the owner cannot delete a used promo code either');
reset role;
select followup_test.fail_unless(
  exists (select 1 from public.promo_codes where id = followup_test.promo_id(1))
  and (select count(*) = 1 from public.promo_code_redemptions where promo_code_id = followup_test.promo_id(1))
  and exists (select 1 from public.promo_codes where id = followup_test.promo_id(6)),
  'without the policy the refused deletes removed no code and no redemption');
-- A customer still deletes nothing (RLS on promo_codes).
select followup_test.sign_in('81000000-0000-0000-0000-000000000001');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt('delete from public.promo_codes where code like ''%8_''') = 'ok',
  'without the policy a customer delete still matches no rows');
reset role;
select followup_test.fail_unless(
  (select count(*) = 5 from public.promo_codes where code like '%8_'),
  'without the policy a customer deleted nothing');
-- Staff can still delete an unused code.
select followup_test.sign_in('81000000-0000-0000-0000-000000000002');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(6))) = 'ok',
  format('without the policy staff can still delete an unused promo code, got %s',
         followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(6)))));
reset role;
select followup_test.sign_in(null);
select followup_test.fail_unless(
  not exists (select 1 from public.promo_codes where id = followup_test.promo_id(6)),
  'without the policy the unused promo code is gone');
-- The service role and the database owner are not restricted.
set local role service_role;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(7))) = 'ok',
  'without the policy the service role can delete a used promo code');
reset role;
select followup_test.fail_unless(
  current_user = 'postgres'
  and followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(8))) = 'ok',
  'without the policy the database owner can delete a used promo code');
select followup_test.fail_unless(
  not exists (select 1 from public.promo_codes
               where id in (followup_test.promo_id(7), followup_test.promo_id(8)))
  and not exists (select 1 from public.promo_code_redemptions
                   where promo_code_id in (followup_test.promo_id(7), followup_test.promo_id(8))),
  'the service-role and owner deletes cascaded');
rollback to savepoint without_redemptions_policy;
select followup_test.fail_unless(
  exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'promo_code_redemptions'
             and policyname = 'Admins can view promo redemptions'),
  'the policy is back after the savepoint');

-- A caller the helper does not answer is stopped, not waved through: here
-- a signed-in non-admin who (hypothetically) were allowed to delete codes.
savepoint loose_delete_policy;
create policy "test: anyone can read and delete promo codes" on public.promo_codes
  for all to authenticated using (true);
select followup_test.sign_in('81000000-0000-0000-0000-000000000001');
set local role authenticated;
select followup_test.fail_unless(
  followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(1))) = 'denied'
  and followup_test.attempt(format('delete from public.promo_codes where id = %L', followup_test.promo_id(6))) = 'denied',
  'a non-admin who reaches the guard is refused the same way for a used and an unused code');
reset role;
select followup_test.sign_in(null);
rollback to savepoint loose_delete_policy;
select followup_test.fail_unless(
  (select count(*) = 4 from public.promo_codes
    where id in (select followup_test.promo_id(n) from unnest(array[1, 6, 7, 8]) n)),
  'nothing was deleted through the loose policy');

-- =====================================================================
-- 4. settings.gst_percent defaults to 0 (the shop is not GST-registered)
-- =====================================================================
select followup_test.fail_unless(
  (select pg_get_expr(d.adbin, d.adrelid) = '0'
     from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'public.settings'::regclass and a.attname = 'gst_percent'),
  'settings.gst_percent defaults to 0');

rollback;
