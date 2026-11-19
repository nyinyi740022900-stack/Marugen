-- Disposable database only. Checks migration 0078 against the full schema.
-- All fixtures are synthetic and rolled back.
\set ON_ERROR_STOP on
begin;

-- Helpers live in a schema that is rolled back with everything else.
create schema sprint3_test;
create function sprint3_test.fail_unless(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', message; end if;
end $$;
-- Runs a statement as the current role and reports how it ended:
-- 'ok', 'denied' (no privilege / RLS), or 'rejected: <message>'.
create function sprint3_test.attempt(statement text) returns text
language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception
  when insufficient_privilege then return 'denied';
  when others then return 'rejected: ' || sqlerrm;
end $$;
grant usage on schema sprint3_test to anon, authenticated, service_role;

-- =====================================================================
-- Fixtures
-- =====================================================================
insert into auth.users (id, email) values
  ('78000000-0000-0000-0000-000000000001', 'buyer@example.invalid'),
  ('78000000-0000-0000-0000-000000000002', 'staff@example.invalid'),
  ('78000000-0000-0000-0000-000000000004', 'owner@example.invalid'),
  ('78000000-0000-0000-0000-000000000005', 'customer-two@example.invalid');
update public.profiles set role = 'staff' where id = '78000000-0000-0000-0000-000000000002';
update public.profiles set role = 'owner' where id = '78000000-0000-0000-0000-000000000004';

insert into public.products (id, name, category, price, stock_quantity) values
  ('78100000-0000-0000-0000-000000000001', 'Test pellets', 'fish_food', 10, 100),
  ('78100000-0000-0000-0000-000000000002', 'Test net', 'accessories', 25, 100),
  ('78100000-0000-0000-0000-000000000003', 'Test gone', 'accessories', 5, 100),
  -- A second product that happens to share a name (relisted stock).
  ('78100000-0000-0000-0000-000000000004', 'Test pellets', 'fish_food', 10, 100);

-- =====================================================================
-- 1. GST snapshot
-- =====================================================================
select sprint3_test.fail_unless(
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'orders' and is_nullable = 'YES'
      and (column_name, data_type) in (
        ('gst_percent', 'numeric'),
        ('gst_included_in_price', 'boolean'),
        ('gst_amount_cents', 'integer'))) = 3,
  'orders has nullable gst_percent numeric, gst_included_in_price boolean, gst_amount_cents integer');
select sprint3_test.fail_unless(
  (select gst_percent is null and gst_included_in_price is null and gst_amount_cents is null
     from public.orders where id = '78200000-0000-0000-0000-0000000000f1'),
  'an order placed before 0078 is not backfilled with today''s rate (run twice)');

-- The payment backend writes the snapshot when it creates the order,
-- exactly as create-payment-intent does.
set local role service_role;
insert into public.orders (id, user_id, status, total, idempotency_key,
                           gst_percent, gst_included_in_price, gst_amount_cents) values
  ('78200000-0000-0000-0000-000000000010', '78000000-0000-0000-0000-000000000001',
   'pending', 109, 's3-gst-key-0001', 9, true, 900);
reset role;
select sprint3_test.fail_unless(
  (select gst_percent = 9 and gst_included_in_price and gst_amount_cents = 900
     from public.orders where id = '78200000-0000-0000-0000-000000000010'),
  'service role stores the GST snapshot on a new order');

-- Half a snapshot, or a nonsense one, is refused whoever writes it.
select sprint3_test.fail_unless(
  sprint3_test.attempt(format($q$
    insert into public.orders (user_id, status, total, %s)
    values ('78000000-0000-0000-0000-000000000001', 'pending', 10, %s)$q$, cols, vals))
    like 'rejected:%orders_gst_snapshot_complete%',
  format('snapshot (%s) = (%s) is refused', cols, vals))
  from (values
    ('gst_percent', '9'),
    ('gst_percent, gst_included_in_price', '9, true'),
    ('gst_amount_cents', '900'),
    ('gst_percent, gst_included_in_price, gst_amount_cents', '9, true, -1'),
    ('gst_percent, gst_included_in_price, gst_amount_cents', '-1, true, 0'),
    ('gst_percent, gst_included_in_price, gst_amount_cents', '101, false, 0')
  ) as bad(cols, vals);

-- Staff, through the API role and the real "Admins can update orders" policy.
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select sprint3_test.fail_unless(
  sprint3_test.attempt(format(
    'update public.orders set %s where id = ''78200000-0000-0000-0000-000000000010''', change))
    like 'rejected:%',
  format('staff cannot %s on an order with a snapshot', change))
  from unnest(array[
    'gst_percent = 0',
    'gst_included_in_price = false',
    'gst_amount_cents = 1',
    'gst_percent = null, gst_included_in_price = null, gst_amount_cents = null',
    'total = 1']) change;
-- ... nor write one onto an order that has none.
select sprint3_test.fail_unless(
  sprint3_test.attempt(
    'update public.orders set gst_percent = 0, gst_included_in_price = true, gst_amount_cents = 0
      where id = ''78200000-0000-0000-0000-0000000000f1''')
    like 'rejected:%payment backend%',
  'staff cannot add a GST snapshot to an old order');
-- Fulfilment is still theirs.
select sprint3_test.fail_unless(
  sprint3_test.attempt(
    'update public.orders set status = ''packing''
      where id = ''78200000-0000-0000-0000-0000000000f1''') = 'ok',
  'staff can still move a paid order to packing');
reset role;
select sprint3_test.fail_unless(
  (select status from public.orders where id = '78200000-0000-0000-0000-0000000000f1') = 'packing',
  'the staff status change was saved');

-- The customer who owns the order, through the API role.
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.orders set gst_percent = 0, gst_amount_cents = 0, total = 1
 where id = '78200000-0000-0000-0000-000000000010';
select sprint3_test.fail_unless(
  sprint3_test.attempt($q$
    insert into public.orders (user_id, status, total, gst_percent, gst_included_in_price, gst_amount_cents)
    values ('78000000-0000-0000-0000-000000000001', 'pending', 1, 0, true, 0)$q$) <> 'ok',
  'a customer cannot insert an order (with or without a GST snapshot)');
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
update public.orders set gst_percent = 0, gst_amount_cents = 0
 where id = '78200000-0000-0000-0000-000000000010';
reset role;
select sprint3_test.fail_unless(
  (select total = 109 and gst_percent = 9 and gst_included_in_price and gst_amount_cents = 900
     from public.orders where id = '78200000-0000-0000-0000-000000000010'),
  'customer and anonymous updates changed nothing');

-- Written once: not even the backend restates a snapshot.
set local role service_role;
select sprint3_test.fail_unless(
  sprint3_test.attempt(format(
    'update public.orders set %s where id = ''78200000-0000-0000-0000-000000000010''', change))
    like 'rejected:%immutable%',
  format('service role cannot %s once the snapshot exists', change))
  from unnest(array[
    'gst_percent = 8',
    'gst_amount_cents = 800',
    'gst_percent = null, gst_included_in_price = null, gst_amount_cents = null']) change;
-- Its other writes on the same order are unaffected.
select sprint3_test.fail_unless(
  sprint3_test.attempt(
    'update public.orders set stripe_payment_intent_id = ''pi_s3_gst''
      where id = ''78200000-0000-0000-0000-000000000010''') = 'ok',
  'service role can still link the PaymentIntent');
reset role;

-- =====================================================================
-- 2. EasyParcel token refresh lease
-- =====================================================================
select sprint3_test.fail_unless(
  not has_function_privilege(r, 'public.claim_easyparcel_token_refresh(text)', 'execute'),
  format('%s cannot execute claim_easyparcel_token_refresh', r))
  from unnest(array['anon', 'authenticated']) r;
insert into public.easyparcel_connection
  (id, access_token, refresh_token, access_token_expires_at, refresh_token_expires_at)
values (1, 'access-test', 'refresh-test', now() - interval '1 minute', now() + interval '30 days');
set local role service_role;
select sprint3_test.fail_unless(
  not public.claim_easyparcel_token_refresh('some-other-token'),
  'a stale refresh token cannot take the lease');
select sprint3_test.fail_unless(
  public.claim_easyparcel_token_refresh('refresh-test'),
  'the first refresher takes the lease');
select sprint3_test.fail_unless(
  not public.claim_easyparcel_token_refresh('refresh-test'),
  'a second refresher is refused while the lease is held');
reset role;
update public.easyparcel_connection set refresh_started_at = now() - interval '61 seconds';
set local role service_role;
select sprint3_test.fail_unless(
  public.claim_easyparcel_token_refresh('refresh-test'),
  'an abandoned lease expires after 60 seconds');
reset role;
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select sprint3_test.fail_unless(
  sprint3_test.attempt('select public.claim_easyparcel_token_refresh(''refresh-test'')') = 'denied',
  'staff cannot call claim_easyparcel_token_refresh');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- =====================================================================
-- 3. Indexes
-- =====================================================================
select sprint3_test.fail_unless(
  exists (select 1 from pg_indexes
           where schemaname = 'public' and indexname = want.name
             and indexdef like '%' || want.definition),
  format('index %s exists on %s', want.name, want.definition))
  from (values
    ('order_items_order_id_idx', 'ON public.order_items USING btree (order_id)'),
    ('order_items_product_id_idx', 'ON public.order_items USING btree (product_id)'),
    ('orders_user_id_created_at_idx', 'ON public.orders USING btree (user_id, created_at DESC)'),
    ('orders_status_created_at_idx', 'ON public.orders USING btree (status, created_at DESC)'),
    ('orders_qxpress_tracking_no_idx', 'ON public.orders USING btree (qxpress_tracking_no)'),
    ('orders_easyparcel_shipment_id_idx', 'ON public.orders USING btree (easyparcel_shipment_id)'),
    ('addresses_user_id_idx', 'ON public.addresses USING btree (user_id)'),
    ('product_variants_product_id_idx', 'ON public.product_variants USING btree (product_id)'),
    ('promo_code_redemptions_order_id_idx', 'ON public.promo_code_redemptions USING btree (order_id)')
  ) as want(name, definition);
-- The second run of 0078 did not add duplicates under other names.
select sprint3_test.fail_unless(
  (select count(*) from pg_indexes
    where schemaname = 'public' and tablename = 'order_items'
      and indexdef like '%(order_id)') = 1,
  'order_items(order_id) is indexed exactly once');

-- =====================================================================
-- 4. Admin aggregates
-- =====================================================================
-- Orders are created the way the backend does it (pending, then lines, then
-- status), so the real stock and status triggers run. Expected numbers:
--
--   order  status     total  refunded  PaymentIntent  collected  lines
--   old    packing    109    -         yes            109        Old pellets x1 @109
--   ..10   pending    109    -         yes            0          -
--   ..21   paid       50     -         yes            50         pellets x3, net x1
--   ..22   shipped    100    30        yes            70         pellets x2
--   ..23   refunded   80     80 ok     yes            0          net x2
--   ..24   refunded   60     20 failed yes            40         pellets x1
--   ..25   pending    40     -         yes            0          net x1
--   ..26   cancelled  70     -         yes            0          pellets x50 (not counted)
--   ..27   delivered  25     -         no             -          gone x4 @5 (product deleted)
--   ..28   paid       20     -         ''             -          -
--   ..29   paid       10     15 (over) yes            0          pellets (2nd product) x1
--
--   collected = 109 + 50 + 70 + 40 = 269 over 9 transactions
insert into public.orders (id, user_id, status, total, stripe_payment_intent_id, created_at) values
  ('78200000-0000-0000-0000-000000000021', '78000000-0000-0000-0000-000000000001', 'pending', 50, 'pi_s3_21', now() - interval '9 days'),
  ('78200000-0000-0000-0000-000000000022', '78000000-0000-0000-0000-000000000001', 'pending', 100, 'pi_s3_22', now() - interval '8 days'),
  ('78200000-0000-0000-0000-000000000023', '78000000-0000-0000-0000-000000000001', 'pending', 80, 'pi_s3_23', now() - interval '7 days'),
  ('78200000-0000-0000-0000-000000000024', '78000000-0000-0000-0000-000000000005', 'pending', 60, 'pi_s3_24', now() - interval '6 days'),
  ('78200000-0000-0000-0000-000000000025', '78000000-0000-0000-0000-000000000005', 'pending', 40, 'pi_s3_25', now() - interval '5 days'),
  ('78200000-0000-0000-0000-000000000026', '78000000-0000-0000-0000-000000000005', 'pending', 70, 'pi_s3_26', now() - interval '4 days'),
  ('78200000-0000-0000-0000-000000000027', '78000000-0000-0000-0000-000000000005', 'pending', 25, null, now() - interval '3 days'),
  ('78200000-0000-0000-0000-000000000028', '78000000-0000-0000-0000-000000000005', 'pending', 20, '', now() - interval '2 days'),
  ('78200000-0000-0000-0000-000000000029', '78000000-0000-0000-0000-000000000005', 'pending', 10, 'pi_s3_29', now() - interval '1 day');
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('78200000-0000-0000-0000-000000000021', '78100000-0000-0000-0000-000000000001', 'Test pellets', 3, 10),
  ('78200000-0000-0000-0000-000000000021', '78100000-0000-0000-0000-000000000002', 'Test net', 1, 25),
  ('78200000-0000-0000-0000-000000000022', '78100000-0000-0000-0000-000000000001', 'Test pellets', 2, 10),
  ('78200000-0000-0000-0000-000000000023', '78100000-0000-0000-0000-000000000002', 'Test net', 2, 25),
  ('78200000-0000-0000-0000-000000000024', '78100000-0000-0000-0000-000000000001', 'Test pellets', 1, 10),
  ('78200000-0000-0000-0000-000000000025', '78100000-0000-0000-0000-000000000002', 'Test net', 1, 25),
  ('78200000-0000-0000-0000-000000000026', '78100000-0000-0000-0000-000000000001', 'Test pellets', 50, 10),
  ('78200000-0000-0000-0000-000000000027', '78100000-0000-0000-0000-000000000003', 'Test gone', 4, 5),
  ('78200000-0000-0000-0000-000000000029', '78100000-0000-0000-0000-000000000004', 'Test pellets', 1, 10);
update public.orders set status = 'paid'
 where id::text like '78200000-0000-0000-0000-00000000002_'
   and id::text not like '%5' and id::text not like '%6';
update public.orders set status = 'cancelled' where id = '78200000-0000-0000-0000-000000000026';
update public.orders set status = 'shipped', refund_amount = 30, refund_status = 'partially_refunded'
 where id = '78200000-0000-0000-0000-000000000022';
update public.orders set status = 'refunded', refund_amount = 80, refund_status = 'succeeded', refunded_at = now()
 where id = '78200000-0000-0000-0000-000000000023';
update public.orders set status = 'refunded', refund_amount = 20, refund_status = 'failed'
 where id = '78200000-0000-0000-0000-000000000024';
update public.orders set status = 'shipped' where id = '78200000-0000-0000-0000-000000000027';
update public.orders set status = 'delivered' where id = '78200000-0000-0000-0000-000000000027';
update public.orders set refund_amount = 15, refund_status = 'partially_refunded'
 where id = '78200000-0000-0000-0000-000000000029';
delete from public.products where id = '78100000-0000-0000-0000-000000000003';

select sprint3_test.fail_unless(
  (select string_agg(status, ',' order by id) from public.orders
    where id::text like '78200000-0000-0000-0000-00000000002_')
    = 'paid,shipped,refunded,refunded,pending,cancelled,delivered,paid,paid',
  'aggregate fixture orders reached their intended statuses');

-- Grants follow admin_order_summary (0074).
select sprint3_test.fail_unless(
  not has_function_privilege('anon', f, 'execute')
  and has_function_privilege('authenticated', f, 'execute'),
  format('%s: anon cannot execute, authenticated can', f))
  from unnest(array[
    'public.admin_payments_summary()',
    'public.admin_top_products(integer)']) f;
select sprint3_test.fail_unless(
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=public, pg_temp'])
     from pg_proc p
    where p.oid in ('public.admin_payments_summary()'::regprocedure,
                    'public.admin_top_products(integer)'::regprocedure,
                    'public.claim_easyparcel_token_refresh(text)'::regprocedure)),
  'the new SECURITY DEFINER functions pin search_path');

-- Anonymous visitor and signed-in customer: refused, by real calls.
set local role anon;
select sprint3_test.fail_unless(
  sprint3_test.attempt('select * from public.admin_payments_summary()') = 'denied'
  and sprint3_test.attempt('select * from public.admin_top_products(10)') = 'denied',
  'anon cannot read payments totals or top products');
reset role;
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select sprint3_test.fail_unless(
  sprint3_test.attempt('select * from public.admin_payments_summary()') = 'denied'
  and sprint3_test.attempt('select * from public.admin_top_products(10)') = 'denied',
  'a customer cannot read payments totals or top products');
reset role;

-- Staff and owner, through the API role.
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select sprint3_test.fail_unless(
  (select transaction_count = 9 and collected = 269 from public.admin_payments_summary()),
  format('staff: payments summary is 9 transactions / 269 collected, got %s',
         (select row_to_json(s) from public.admin_payments_summary() s)));
select sprint3_test.fail_unless(
  (select string_agg(format('%s=%s/%s/%s', product_name, units, revenue,
                            coalesce(right(product_id::text, 2), 'null')), ' ' order by ord)
     from public.admin_top_products() with ordinality t(product_name, product_id, units, revenue, ord))
    = 'Test pellets=7/70.00/04 Test gone=4/20.00/null Test net=4/100.00/02 Old pellets=1/109.00/f1',
  format('staff: top products ranking, got %s',
         (select string_agg(format('%s=%s/%s/%s', product_name, units, revenue,
                                   coalesce(right(product_id::text, 2), 'null')), ' ' order by ord)
            from public.admin_top_products() with ordinality t(product_name, product_id, units, revenue, ord))));
select sprint3_test.fail_unless(
  (select count(*) from public.admin_top_products(2)) = 2
  and (select count(*) from public.admin_top_products(0)) = 1
  and (select count(*) from public.admin_top_products(null)) = 4
  and (select product_name from public.admin_top_products(1)) = 'Test pellets',
  'top products honours p_limit (clamped to at least 1)');
reset role;
select set_config('request.jwt.claim.sub', '78000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select sprint3_test.fail_unless(
  (select transaction_count = 9 and collected = 269 from public.admin_payments_summary())
  and (select count(*) from public.admin_top_products()) = 4,
  'owner reads the same totals');
reset role;
select set_config('request.jwt.claim.sub', '', true);

rollback;
