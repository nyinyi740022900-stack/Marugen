-- Migration 0053 integration checks; disposable database only, all rolled back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.expect_payment_rejection(statement text) returns void
language plpgsql as $$
declare rejected boolean := false;
begin
  begin execute statement;
  exception when raise_exception then rejected := true; end;
  if not rejected then raise exception 'Expected payment cancellation rejection: %', statement; end if;
end;
$$;
insert into auth.users(id,email) values
('80000000-0000-0000-0000-000000000001','cancel-customer@example.invalid'),
('80000000-0000-0000-0000-000000000002','cancel-admin@example.invalid');
update public.profiles set role='owner' where id='80000000-0000-0000-0000-000000000002';
insert into public.products(id,name,category,price,stock_quantity) values
('80000000-0000-0000-0000-000000000003','Cancel food','fish_food',10,10);
insert into public.orders(id,user_id,status,stripe_payment_intent_id,created_at) values
('81000000-0000-0000-0000-000000000001','80000000-0000-0000-0000-000000000001','pending','pi_boundary_customer',now()-interval '1 hour'),
('81000000-0000-0000-0000-000000000002','80000000-0000-0000-0000-000000000001','pending','pi_boundary_service',now()-interval '1 hour'),
('81000000-0000-0000-0000-000000000003','80000000-0000-0000-0000-000000000001','pending','pi_boundary_paid',now()-interval '1 hour'),
('81000000-0000-0000-0000-000000000004','80000000-0000-0000-0000-000000000001','pending','pi_boundary_packing',now()-interval '1 hour'),
('81000000-0000-0000-0000-000000000005','80000000-0000-0000-0000-000000000001','pending',null,now()-interval '1 hour');
insert into public.order_items(order_id,product_id,product_name,quantity)
select id,'80000000-0000-0000-0000-000000000003','Cancel food',1 from public.orders where id::text like '81000000%';
update public.orders set status='paid' where id in ('81000000-0000-0000-0000-000000000003','81000000-0000-0000-0000-000000000004');
update public.orders set status='packing' where id='81000000-0000-0000-0000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
update public.orders set status='cancelled' where id in
('81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000003');
do $$ begin
  if exists(select 1 from public.orders where id in
    ('81000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000003') and status='cancelled') then
    raise exception 'Customer direct cancellation unexpectedly allowed';
  end if;
end $$;
select set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000002',true);
-- Status-only guards miss the first step of clearing a link, then cancelling.
select pg_temp.expect_payment_rejection($$update public.orders set stripe_payment_intent_id=null where id='81000000-0000-0000-0000-000000000001'$$);
select pg_temp.expect_payment_rejection($$update public.orders set stripe_payment_intent_id='pi_forged_admin' where id='81000000-0000-0000-0000-000000000001'$$);
select pg_temp.expect_payment_rejection($$update public.orders set stripe_payment_intent_id='pi_forged_orphan' where id='81000000-0000-0000-0000-000000000005'$$);
select pg_temp.expect_payment_rejection($$update public.orders set status='cancelled' where id='81000000-0000-0000-0000-000000000001'$$);
select pg_temp.expect_payment_rejection($$update public.orders set status='cancelled' where id='81000000-0000-0000-0000-000000000003'$$);
select pg_temp.expect_payment_rejection($$update public.orders set status='cancelled' where id='81000000-0000-0000-0000-000000000004'$$);
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim.role','service_role',true);
select pg_temp.expect_payment_rejection($$update public.orders set stripe_payment_intent_id=null where id='81000000-0000-0000-0000-000000000001'$$);
select pg_temp.expect_payment_rejection($$update public.orders set stripe_payment_intent_id='pi_replaced_service' where id='81000000-0000-0000-0000-000000000001'$$);
-- Linking a newly-created order remains a legitimate backend operation.
insert into public.orders(id,user_id) values ('81000000-0000-0000-0000-000000000006','80000000-0000-0000-0000-000000000001');
update public.orders set stripe_payment_intent_id='pi_new_service_link' where id='81000000-0000-0000-0000-000000000006';
update public.orders set status='cancelled' where id='81000000-0000-0000-0000-000000000002';
select pg_temp.expect_payment_rejection($$update public.orders set status='cancelled' where id='81000000-0000-0000-0000-000000000003'$$);
select pg_temp.expect_payment_rejection($$update public.orders set status='cancelled' where id='81000000-0000-0000-0000-000000000004'$$);
reset role;
select pg_temp.expect_payment_rejection($$update public.orders set status='cancelled' where id='81000000-0000-0000-0000-000000000003'$$);
select public.cancel_stale_pending_orders();
do $$ begin
  if (select status from public.orders where id='81000000-0000-0000-0000-000000000001') <> 'pending' then
    raise exception 'Cron cancelled a linked payment';
  end if;
  if (select status from public.orders where id='81000000-0000-0000-0000-000000000002') <> 'cancelled' then
    raise exception 'Verified service cancellation did not succeed';
  end if;
  if (select status from public.orders where id='81000000-0000-0000-0000-000000000005') <> 'cancelled' then
    raise exception 'Cron failed to release an orphan pending reservation';
  end if;
  if (select stock_quantity from public.products where id='80000000-0000-0000-0000-000000000003') <> 7 then
    raise exception 'Stock restored for unverified/paid cancellation or failed to restore for legitimate cancellation';
  end if;
end $$;
-- Paid orders still use the refund path.
set local role service_role;
update public.orders set status='refunded' where id='81000000-0000-0000-0000-000000000003';
reset role;
select 'Verified payment cancellation integration checks passed' as result;
rollback;
