-- Disposable database only. Checks migration 0077 against the full schema.
-- All fixtures are synthetic and rolled back.
\set ON_ERROR_STOP on
begin;

-- Helpers live in a schema that is rolled back with everything else.
create schema sprint1_test;
create function sprint1_test.fail_unless(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', message; end if;
end $$;
grant usage on schema sprint1_test to anon, authenticated, service_role;

-- =====================================================================
-- History: what 0077 did with orders that finished before it ran.
-- =====================================================================
select sprint1_test.fail_unless(
  exists (select 1 from public.order_stock_restorations
           where order_id = '77200000-0000-0000-0000-0000000000f1' and to_status = 'cancelled'),
  'an order cancelled before 0077 is recorded as already restored');
select sprint1_test.fail_unless(
  not exists (select 1 from public.order_stock_restorations
               where order_id = '77200000-0000-0000-0000-0000000000f2'),
  'an order refunded before 0077 is not recorded as restored');
select sprint1_test.fail_unless(
  (select stock_quantity from public.products where id = '77100000-0000-0000-0000-0000000000f1') = 4,
  '0077 does not silently change stock for orders refunded before it (run twice)');

-- =====================================================================
-- Fixtures
-- =====================================================================
insert into auth.users (id, email) values
  ('77000000-0000-0000-0000-000000000001', 'buyer@example.invalid'),
  ('77000000-0000-0000-0000-000000000002', 'staff@example.invalid'),
  ('77000000-0000-0000-0000-000000000003', 'staff-two@example.invalid'),
  ('77000000-0000-0000-0000-000000000004', 'owner@example.invalid'),
  ('77000000-0000-0000-0000-000000000005', 'customer-two@example.invalid');
-- No user session here (as in the SQL editor): appointing roles is allowed.
update public.profiles set role = 'staff'
 where id in ('77000000-0000-0000-0000-000000000002', '77000000-0000-0000-0000-000000000003');
update public.profiles set role = 'owner' where id = '77000000-0000-0000-0000-000000000004';
select sprint1_test.fail_unless(
  (select count(*) from public.profiles
    where id::text like '77000000-0000-0000-0000-00000000000_' and role <> 'customer') = 3,
  'a session with no user (service role / SQL editor) can still set roles');

insert into public.products (id, name, category, price, stock_quantity) values
  ('77100000-0000-0000-0000-000000000001', 'Test Kohaku', 'koi', 100, 1),
  ('77100000-0000-0000-0000-000000000002', 'Test net', 'accessories', 10, 10);
insert into public.promo_codes (id, code, discount_type, discount_value, max_redemptions)
  values ('77300000-0000-0000-0000-000000000001', 'SPRINT1', 'percent', 10, 5);

-- =====================================================================
-- 1. order_number_counters
-- =====================================================================
select sprint1_test.fail_unless(
  (select relrowsecurity from pg_class where oid = 'public.order_number_counters'::regclass),
  'order_number_counters has RLS enabled');
select sprint1_test.fail_unless(
  not has_table_privilege(r, 'public.order_number_counters', p),
  format('%s has no %s on order_number_counters', r, p))
  from unnest(array['anon', 'authenticated']) r,
       unnest(array['select', 'insert', 'update', 'delete', 'truncate']) p;

-- The order number trigger still works for the payment backend.
set local role service_role;
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-000000000009', '77000000-0000-0000-0000-000000000001', 'pending', 1);
reset role;
select sprint1_test.fail_unless(
  (select order_number ~ '^\d{8}-\d{4}$' from public.orders
    where id = '77200000-0000-0000-0000-000000000009'),
  'service-role order insert still gets an order number');

-- =====================================================================
-- 2. Server-only RPCs
-- =====================================================================
select sprint1_test.fail_unless(
  not has_function_privilege(r, f, 'execute'), format('%s cannot execute %s', r, f))
  from unnest(array['anon', 'authenticated']) r,
       unnest(array[
         'public.claim_promo_redemption(uuid)',
         'public.release_promo_redemption(uuid)',
         'public.cancel_stale_pending_orders()',
         'public.reconcile_pending_orders()',
         'public.restore_stock_on_cancel()',
         'public.prevent_role_self_escalation()',
         'public.assign_order_number()',
         'public.apply_order_item_stock()',
         'public.handle_new_user()']) f;
select sprint1_test.fail_unless(
  has_function_privilege('service_role', f, 'execute'), format('service_role can execute %s', f))
  from unnest(array[
         'public.claim_promo_redemption(uuid)',
         'public.release_promo_redemption(uuid)',
         'public.cancel_stale_pending_orders()',
         'public.reconcile_pending_orders()']) f;
-- What clients legitimately need is untouched.
select sprint1_test.fail_unless(
  has_function_privilege(r, 'public.is_admin()', 'execute')
  and has_function_privilege(r, 'public.get_product_stats()', 'execute'),
  format('%s keeps is_admin() and get_product_stats()', r))
  from unnest(array['anon', 'authenticated']) r;
select sprint1_test.fail_unless(
  has_function_privilege('authenticated', f, 'execute'), format('authenticated keeps %s', f))
  from unnest(array[
         'public.set_default_address(uuid)',
         'public.check_promo_code(text)',
         'public.confirm_shop_delivery(uuid)',
         'public.admin_order_summary()',
         'public.admin_daily_activity(integer)',
         'public.admin_top_viewed_products(timestamptz,integer)',
         'public.register_device_token(text,text)',
         'public.unregister_device_token(text)']) f;

-- Real attempts, as a signed-in customer and as an anonymous visitor.
select set_config('request.jwt.claim.sub', '77000000-0000-0000-0000-000000000001', true);
set local role authenticated;
do $$
declare denied int := 0;
begin
  begin perform public.claim_promo_redemption('77300000-0000-0000-0000-000000000001');
  exception when insufficient_privilege then denied := denied + 1; end;
  begin perform public.release_promo_redemption('77300000-0000-0000-0000-000000000001');
  exception when insufficient_privilege then denied := denied + 1; end;
  begin perform public.cancel_stale_pending_orders();
  exception when insufficient_privilege then denied := denied + 1; end;
  begin perform public.reconcile_pending_orders();
  exception when insufficient_privilege then denied := denied + 1; end;
  begin insert into public.order_number_counters (day, counter) values ('2000-01-01', 9999);
  exception when insufficient_privilege then denied := denied + 1; end;
  begin update public.order_number_counters set counter = 0;
  exception when insufficient_privilege then denied := denied + 1; end;
  begin delete from public.order_number_counters;
  exception when insufficient_privilege then denied := denied + 1; end;
  begin perform 1 from public.order_number_counters;
  exception when insufficient_privilege then denied := denied + 1; end;
  if denied <> 8 then
    raise exception 'FAILED: authenticated was denied only % of 8 forbidden actions', denied;
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
declare denied int := 0;
begin
  begin perform public.claim_promo_redemption('77300000-0000-0000-0000-000000000001');
  exception when insufficient_privilege then denied := denied + 1; end;
  begin perform public.release_promo_redemption('77300000-0000-0000-0000-000000000001');
  exception when insufficient_privilege then denied := denied + 1; end;
  begin perform public.cancel_stale_pending_orders();
  exception when insufficient_privilege then denied := denied + 1; end;
  begin perform public.reconcile_pending_orders();
  exception when insufficient_privilege then denied := denied + 1; end;
  begin update public.order_number_counters set counter = 0;
  exception when insufficient_privilege then denied := denied + 1; end;
  if denied <> 5 then
    raise exception 'FAILED: anon was denied only % of 5 forbidden actions', denied;
  end if;
end $$;
reset role;
select sprint1_test.fail_unless(
  (select times_redeemed from public.promo_codes where id = '77300000-0000-0000-0000-000000000001') = 0,
  'no promo slot was claimed by a client');

-- The backend path still works.
set local role service_role;
select sprint1_test.fail_unless(
  public.claim_promo_redemption('77300000-0000-0000-0000-000000000001'),
  'service_role can claim a promo slot');
select public.release_promo_redemption('77300000-0000-0000-0000-000000000001');
select public.cancel_stale_pending_orders();
reset role;

-- =====================================================================
-- 3. Role changes
-- =====================================================================
-- Staff, through the API role and real RLS: own row.
select set_config('request.jwt.claim.sub', '77000000-0000-0000-0000-000000000002', true);
set local role authenticated;
update public.profiles set role = 'owner', full_name = 'Staff One'
 where id = '77000000-0000-0000-0000-000000000002';
-- Staff, through the API role: someone else's row.
update public.profiles set role = 'owner' where id = '77000000-0000-0000-0000-000000000005';
update public.profiles set role = 'customer' where id = '77000000-0000-0000-0000-000000000004';
reset role;
select sprint1_test.fail_unless(
  (select role = 'staff' and full_name = 'Staff One' from public.profiles
    where id = '77000000-0000-0000-0000-000000000002'),
  'staff cannot change own role; the rest of the profile edit still saves');
select sprint1_test.fail_unless(
  (select role from public.profiles where id = '77000000-0000-0000-0000-000000000005') = 'customer'
  and (select role from public.profiles where id = '77000000-0000-0000-0000-000000000004') = 'owner',
  'staff cannot change another user''s role');

-- The trigger alone, with RLS out of the way (role postgres, user claim set),
-- so the rule holds even if a broader profiles UPDATE policy is added later.
update public.profiles set role = 'owner' where id = '77000000-0000-0000-0000-000000000005';
update public.profiles set role = 'customer' where id = '77000000-0000-0000-0000-000000000003';
select sprint1_test.fail_unless(
  (select role from public.profiles where id = '77000000-0000-0000-0000-000000000005') = 'customer'
  and (select role from public.profiles where id = '77000000-0000-0000-0000-000000000003') = 'staff',
  'trigger: staff cannot promote or demote another user');

-- Customer promoting themselves (the original 0036 case).
select set_config('request.jwt.claim.sub', '77000000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.profiles set role = 'owner' where id = '77000000-0000-0000-0000-000000000001';
reset role;
select sprint1_test.fail_unless(
  (select role from public.profiles where id = '77000000-0000-0000-0000-000000000001') = 'customer',
  'customer cannot change own role');

-- Owner.
select set_config('request.jwt.claim.sub', '77000000-0000-0000-0000-000000000004', true);
update public.profiles set role = 'staff' where id = '77000000-0000-0000-0000-000000000005';
select sprint1_test.fail_unless(
  (select role from public.profiles where id = '77000000-0000-0000-0000-000000000005') = 'staff',
  'owner can change another user''s role');
update public.profiles set role = 'customer' where id = '77000000-0000-0000-0000-000000000005';
update public.profiles set role = 'customer' where id = '77000000-0000-0000-0000-000000000004';
select sprint1_test.fail_unless(
  (select role from public.profiles where id = '77000000-0000-0000-0000-000000000004') = 'owner',
  'owner cannot change own role');
-- One statement over every row: the owner's own row is still kept.
update public.profiles set role = 'staff' where id::text like '77000000-0000-0000-0000-00000000000_';
select sprint1_test.fail_unless(
  (select role from public.profiles where id = '77000000-0000-0000-0000-000000000004') = 'owner',
  'owner cannot change own role inside a bulk update');
select set_config('request.jwt.claim.sub', '', true);
-- Put the two customers back for the checks below.
update public.profiles set role = 'customer'
 where id in ('77000000-0000-0000-0000-000000000001', '77000000-0000-0000-0000-000000000005');

-- =====================================================================
-- 4. Stock on refund
--    Koi 77100...01 starts at stock 1 / unsold, net 77100...02 at 10.
-- =====================================================================
create function sprint1_test.stock(p uuid) returns int language sql as
  $$ select stock_quantity from public.products where id = p $$;
create function sprint1_test.net() returns int language sql as
  $$ select sprint1_test.stock('77100000-0000-0000-0000-000000000002') $$;

-- Order 1: the koi and 2 nets, S$120, paid.
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-000000000001', '77000000-0000-0000-0000-000000000001', 'pending', 120);
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('77200000-0000-0000-0000-000000000001', '77100000-0000-0000-0000-000000000001', 'Test Kohaku', 1, 100),
  ('77200000-0000-0000-0000-000000000001', '77100000-0000-0000-0000-000000000002', 'Test net', 2, 10);
update public.orders set status = 'paid', stripe_payment_intent_id = 'pi_sprint1_1'
 where id = '77200000-0000-0000-0000-000000000001';
select sprint1_test.fail_unless(
  sprint1_test.net() = 8 and (select is_sold and stock_quantity = 0 from public.products
                          where id = '77100000-0000-0000-0000-000000000001'),
  'fixture: paid order holds the koi and 2 nets');

-- A partial refund leaves the order paid and must not return stock.
set local role service_role;
select public.record_verified_refund('77200000-0000-0000-0000-000000000001', 'pi_sprint1_1',
  're_sprint1_part', 2000, 'sgd', 'succeeded', now(), null);
reset role;
select sprint1_test.fail_unless(
  (select status = 'paid' and refund_status = 'partially_refunded' from public.orders
    where id = '77200000-0000-0000-0000-000000000001')
  and sprint1_test.net() = 8
  and (select is_sold from public.products where id = '77100000-0000-0000-0000-000000000001')
  and not exists (select 1 from public.order_stock_restorations
                   where order_id = '77200000-0000-0000-0000-000000000001'),
  'a partial refund does not return stock');

-- A pending (not yet succeeded) refund for the rest does not either.
set local role service_role;
select public.record_verified_refund('77200000-0000-0000-0000-000000000001', 'pi_sprint1_1',
  're_sprint1_rest', 10000, 'sgd', 'pending', now(), null);
reset role;
select sprint1_test.fail_unless(
  sprint1_test.net() = 8 and (select status from public.orders
                          where id = '77200000-0000-0000-0000-000000000001') = 'paid',
  'a pending refund does not return stock');

-- The rest succeeds: paid -> refunded through the verified refund path.
set local role service_role;
select public.record_verified_refund('77200000-0000-0000-0000-000000000001', 'pi_sprint1_1',
  're_sprint1_rest', 10000, 'sgd', 'succeeded', now(), null);
reset role;
select sprint1_test.fail_unless(
  (select status from public.orders where id = '77200000-0000-0000-0000-000000000001') = 'refunded'
  and sprint1_test.net() = 10
  and (select not is_sold and stock_quantity = 1 from public.products
        where id = '77100000-0000-0000-0000-000000000001'),
  'paid -> refunded returns the nets and relists the koi');
select sprint1_test.fail_unless(
  (select count(*) from public.order_stock_restorations
    where order_id = '77200000-0000-0000-0000-000000000001'
      and from_status = 'paid' and to_status = 'refunded') = 1,
  'the restoration is recorded once');

-- The koi is sold again to someone else. Nothing below may relist it.
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-000000000002', '77000000-0000-0000-0000-000000000005', 'pending', 100);
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('77200000-0000-0000-0000-000000000002', '77100000-0000-0000-0000-000000000001', 'Test Kohaku', 1, 100);

-- Replayed Stripe event for the same refund, and an unrelated update.
set local role service_role;
select public.record_verified_refund('77200000-0000-0000-0000-000000000001', 'pi_sprint1_1',
  're_sprint1_rest', 10000, 'sgd', 'succeeded', now(), null);
update public.orders set tracking_status_detail = 'note' where id = '77200000-0000-0000-0000-000000000001';
update public.orders set status = 'refunded' where id = '77200000-0000-0000-0000-000000000001';
reset role;
select sprint1_test.fail_unless(
  sprint1_test.net() = 10
  and (select is_sold and stock_quantity = 0 from public.products
        where id = '77100000-0000-0000-0000-000000000001'),
  'a replayed refund or an unrelated update does not restore again');

-- Worst case: the state machine is bypassed and the order is walked through
-- paid -> refunded and paid -> cancelled a second time. The ledger still
-- refuses, so the koi now held by order 2 is not put back on sale.
alter table public.orders disable trigger orders_status_forward_only_guard;
alter table public.orders disable trigger orders_verified_payment_cancellation;
update public.orders set status = 'paid' where id = '77200000-0000-0000-0000-000000000001';
update public.orders set status = 'refunded' where id = '77200000-0000-0000-0000-000000000001';
update public.orders set status = 'paid' where id = '77200000-0000-0000-0000-000000000001';
update public.orders set status = 'cancelled' where id = '77200000-0000-0000-0000-000000000001';
update public.orders set status = 'refunded' where id = '77200000-0000-0000-0000-000000000001';
alter table public.orders enable trigger orders_status_forward_only_guard;
alter table public.orders enable trigger orders_verified_payment_cancellation;
select sprint1_test.fail_unless(
  sprint1_test.net() = 10
  and (select is_sold and stock_quantity = 0 from public.products
        where id = '77100000-0000-0000-0000-000000000001')
  and (select count(*) from public.order_stock_restorations
        where order_id = '77200000-0000-0000-0000-000000000001') = 1,
  'an order never restores twice, even cancelled-then-refunded with the guards off');

-- Order 3: 3 nets, packing -> refunded returns them.
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-000000000003', '77000000-0000-0000-0000-000000000001', 'pending', 30);
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('77200000-0000-0000-0000-000000000003', '77100000-0000-0000-0000-000000000002', 'Test net', 3, 10);
update public.orders set status = 'paid', stripe_payment_intent_id = 'pi_sprint1_3'
 where id = '77200000-0000-0000-0000-000000000003';
update public.orders set status = 'packing' where id = '77200000-0000-0000-0000-000000000003';
select sprint1_test.fail_unless(sprint1_test.net() = 7, 'fixture: packing order holds 3 nets');
set local role service_role;
select public.record_verified_refund('77200000-0000-0000-0000-000000000003', 'pi_sprint1_3',
  're_sprint1_3', 3000, 'sgd', 'succeeded', now(), null);
reset role;
select sprint1_test.fail_unless(sprint1_test.net() = 10, 'packing -> refunded returns stock');

-- Order 4: shipped -> refunded. The goods left the shop: nothing returns.
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-000000000004', '77000000-0000-0000-0000-000000000001', 'pending', 10);
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('77200000-0000-0000-0000-000000000004', '77100000-0000-0000-0000-000000000002', 'Test net', 1, 10);
update public.orders set status = 'paid', stripe_payment_intent_id = 'pi_sprint1_4'
 where id = '77200000-0000-0000-0000-000000000004';
update public.orders set status = 'shipped' where id = '77200000-0000-0000-0000-000000000004';
set local role service_role;
select public.record_verified_refund('77200000-0000-0000-0000-000000000004', 'pi_sprint1_4',
  're_sprint1_4', 1000, 'sgd', 'succeeded', now(), null);
reset role;
select sprint1_test.fail_unless(
  (select status from public.orders where id = '77200000-0000-0000-0000-000000000004') = 'refunded'
  and sprint1_test.net() = 9,
  'shipped -> refunded does not return stock');

-- Order 5: delivered -> refunded. Same.
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-000000000005', '77000000-0000-0000-0000-000000000001', 'pending', 10);
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('77200000-0000-0000-0000-000000000005', '77100000-0000-0000-0000-000000000002', 'Test net', 1, 10);
update public.orders set status = 'paid', stripe_payment_intent_id = 'pi_sprint1_5'
 where id = '77200000-0000-0000-0000-000000000005';
update public.orders set status = 'delivered' where id = '77200000-0000-0000-0000-000000000005';
set local role service_role;
select public.record_verified_refund('77200000-0000-0000-0000-000000000005', 'pi_sprint1_5',
  're_sprint1_5', 1000, 'sgd', 'succeeded', now(), null);
reset role;
select sprint1_test.fail_unless(sprint1_test.net() = 8, 'delivered -> refunded does not return stock');

-- Order 6: pending -> cancelled still returns stock, once (the 0020 path).
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-000000000006', '77000000-0000-0000-0000-000000000001', 'pending', 20);
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('77200000-0000-0000-0000-000000000006', '77100000-0000-0000-0000-000000000002', 'Test net', 2, 10);
select sprint1_test.fail_unless(sprint1_test.net() = 6, 'fixture: pending order holds 2 nets');
update public.orders set status = 'cancelled' where id = '77200000-0000-0000-0000-000000000006';
update public.orders set status = 'cancelled' where id = '77200000-0000-0000-0000-000000000006';
select sprint1_test.fail_unless(
  sprint1_test.net() = 8
  and exists (select 1 from public.order_stock_restorations
               where order_id = '77200000-0000-0000-0000-000000000006'
                 and from_status = 'pending' and to_status = 'cancelled'),
  'pending -> cancelled still returns stock exactly once');

-- The ledger itself is closed to clients.
select sprint1_test.fail_unless(
  not has_table_privilege(r, 'public.order_stock_restorations', p),
  format('%s has no %s on order_stock_restorations', r, p))
  from unnest(array['anon', 'authenticated']) r,
       unnest(array['insert', 'update', 'delete', 'truncate']) p;
select sprint1_test.fail_unless(
  not has_table_privilege('anon', 'public.order_stock_restorations', 'select'),
  'anon cannot read order_stock_restorations');
select set_config('request.jwt.claim.sub', '77000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select sprint1_test.fail_unless(
  (select count(*) from public.order_stock_restorations) = 0,
  'a customer sees no stock restoration rows');
reset role;
select set_config('request.jwt.claim.sub', '77000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select sprint1_test.fail_unless(
  (select count(*) from public.order_stock_restorations) > 0,
  'staff can read stock restoration rows');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- =====================================================================
-- 5. Bucket limits
-- =====================================================================
select sprint1_test.fail_unless(
  (select file_size_limit = 10485760
          and allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
          and not allowed_mime_types && array['image/svg+xml', 'application/octet-stream', 'video/mp4']
     from storage.buckets where id = 'product-images'),
  'product-images has a size limit and an image-only type list');

rollback;
