-- Disposable database only. No migration belongs to this file: it pins the
-- database rules create-payment-intent relies on when a repeated checkout
-- key is answered by retiring the old pending order and creating a fresh
-- one (repeatCheckoutAction in _shared/payment_lifecycle.ts). Everything
-- runs as service_role, the role the Edge Function uses.
-- All fixtures are synthetic and rolled back.
\set ON_ERROR_STOP on
begin;

create schema repeat_test;
create function repeat_test.fail_unless(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', message; end if;
end $$;
create function repeat_test.attempt(statement text) returns text
language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception
  when insufficient_privilege then return 'denied';
  when unique_violation then return 'duplicate';
  when others then return 'rejected: ' || sqlerrm;
end $$;
grant usage on schema repeat_test to service_role;

insert into auth.users (id, email) values
  ('79100000-0000-0000-0000-000000000001', 'buyer@example.invalid'),
  ('79100000-0000-0000-0000-000000000002', 'other-buyer@example.invalid');
insert into public.products (id, name, category, price, stock_quantity) values
  ('79200000-0000-0000-0000-000000000001', 'Test Showa', 'koi', 100, 1);
insert into public.promo_codes (id, code, discount_type, discount_value, max_redemptions)
values ('79300000-0000-0000-0000-000000000001', 'REPEAT79', 'fixed', 10, 1);

set local role service_role;

-- The first attempt: pending order, the fish reserved, the promo's only
-- slot claimed, a PaymentIntent linked.
insert into public.orders (id, user_id, status, total, idempotency_key, promo_code, discount_amount)
values ('79400000-0000-0000-0000-000000000001', '79100000-0000-0000-0000-000000000001',
        'pending', 90, 'repeat-key', 'REPEAT79', 10);
insert into public.order_items (order_id, product_id, product_name, product_category, quantity, unit_price)
values ('79400000-0000-0000-0000-000000000001', '79200000-0000-0000-0000-000000000001',
        'Test Showa', 'koi', 1, 100);
select repeat_test.fail_unless(public.claim_promo_redemption('79300000-0000-0000-0000-000000000001'),
  'fixture: the promo slot is claimed');
insert into public.promo_code_redemptions (promo_code_id, user_id, order_id)
values ('79300000-0000-0000-0000-000000000001', '79100000-0000-0000-0000-000000000001',
        '79400000-0000-0000-0000-000000000001');
update public.orders set stripe_payment_intent_id = 'pi_repeat_old'
 where id = '79400000-0000-0000-0000-000000000001';
select repeat_test.fail_unless(
  (select is_sold and stock_quantity = 0 from public.products
    where id = '79200000-0000-0000-0000-000000000001'),
  'fixture: the pending order holds the fish');

-- While the old attempt is live, nothing can stand beside it.
select repeat_test.fail_unless(
  repeat_test.attempt($$insert into public.orders (id, user_id, status, total, idempotency_key)
    values ('79400000-0000-0000-0000-000000000002', '79100000-0000-0000-0000-000000000001',
            'pending', 110, 'repeat-key')$$) = 'duplicate',
  'a second live order with the same checkout key is refused');
insert into public.orders (id, user_id, status, total, idempotency_key)
values ('79400000-0000-0000-0000-000000000003', '79100000-0000-0000-0000-000000000002',
        'pending', 100, 'other-key');
select repeat_test.fail_unless(
  repeat_test.attempt($$insert into public.order_items
      (order_id, product_id, product_name, product_category, quantity, unit_price)
    values ('79400000-0000-0000-0000-000000000003', '79200000-0000-0000-0000-000000000001',
            'Test Showa', 'koi', 1, 100)$$) like 'rejected:%',
  'the reserved fish cannot be reserved by another live order');
select repeat_test.fail_unless(
  (select count(*) from public.order_items
    where product_id = '79200000-0000-0000-0000-000000000001') = 1,
  'exactly one order line holds the fish');
-- The PaymentIntent of a live order can never be swapped for a new one, so
-- a changed total needs a new order rather than a new intent on this one.
select repeat_test.fail_unless(
  repeat_test.attempt($$update public.orders set stripe_payment_intent_id = 'pi_repeat_new'
     where id = '79400000-0000-0000-0000-000000000001'$$) like 'rejected:%',
  'the linked PaymentIntent cannot be replaced');

-- Retirement: the single status update (made only after Stripe confirmed
-- the cancellation) releases the fish and the promo slot in the same
-- statement.
update public.orders set status = 'cancelled'
 where id = '79400000-0000-0000-0000-000000000001'
   and status = 'pending' and stripe_payment_intent_id = 'pi_repeat_old';
select repeat_test.fail_unless(
  (select not is_sold and stock_quantity = 1 from public.products
    where id = '79200000-0000-0000-0000-000000000001'),
  'retiring the order returns the fish');
select repeat_test.fail_unless(
  (select times_redeemed from public.promo_codes
    where id = '79300000-0000-0000-0000-000000000001') = 0
  and not exists (select 1 from public.promo_code_redemptions
                   where order_id = '79400000-0000-0000-0000-000000000001'),
  'retiring the order frees the promo slot and the customer''s redemption');
-- A second "retirement" (two retries racing) changes nothing more.
update public.orders set status = 'cancelled'
 where id = '79400000-0000-0000-0000-000000000001' and status = 'pending';
select repeat_test.fail_unless(
  (select stock_quantity = 1 from public.products
    where id = '79200000-0000-0000-0000-000000000001')
  and (select times_redeemed from public.promo_codes
        where id = '79300000-0000-0000-0000-000000000001') = 0,
  'stock and promo are released exactly once');
select repeat_test.fail_unless(
  repeat_test.attempt($$update public.orders set status = 'pending'
     where id = '79400000-0000-0000-0000-000000000001'$$) <> 'ok'
  or (select status from public.orders
       where id = '79400000-0000-0000-0000-000000000001') = 'cancelled',
  'the retired order cannot come back to life');

-- The fresh order in the same request: same key, new total, same fish,
-- same promo code.
insert into public.orders (id, user_id, status, total, idempotency_key, promo_code, discount_amount)
values ('79400000-0000-0000-0000-000000000004', '79100000-0000-0000-0000-000000000001',
        'pending', 110, 'repeat-key', 'REPEAT79', 10);
insert into public.order_items (order_id, product_id, product_name, product_category, quantity, unit_price)
values ('79400000-0000-0000-0000-000000000004', '79200000-0000-0000-0000-000000000001',
        'Test Showa', 'koi', 1, 120);
select repeat_test.fail_unless(public.claim_promo_redemption('79300000-0000-0000-0000-000000000001'),
  'the fresh order can claim the freed promo slot');
insert into public.promo_code_redemptions (promo_code_id, user_id, order_id)
values ('79300000-0000-0000-0000-000000000001', '79100000-0000-0000-0000-000000000001',
        '79400000-0000-0000-0000-000000000004');
update public.orders set stripe_payment_intent_id = 'pi_repeat_new'
 where id = '79400000-0000-0000-0000-000000000004';
select repeat_test.fail_unless(
  (select is_sold and stock_quantity = 0 from public.products
    where id = '79200000-0000-0000-0000-000000000001'),
  'the fresh order holds the fish');
select repeat_test.fail_unless(
  (select count(*) from public.orders o
     join public.order_items i on i.order_id = o.id
    where i.product_id = '79200000-0000-0000-0000-000000000001'
      and o.status <> 'cancelled') = 1
  and (select count(*) from public.orders
        where user_id = '79100000-0000-0000-0000-000000000001'
          and idempotency_key = 'repeat-key' and status <> 'cancelled') = 1,
  'one live order holds the fish and one live order owns the key');
select repeat_test.fail_unless(
  (select times_redeemed from public.promo_codes
    where id = '79300000-0000-0000-0000-000000000001') = 1,
  'the promo is counted once');
reset role;

rollback;
