-- Disposable database only. Financial values below are synthetic.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values
('f5800000-0000-0000-0000-000000000001','refund-buyer@example.invalid'),
('f5800000-0000-0000-0000-000000000002','refund-owner@example.invalid');
update public.profiles set role='owner' where id='f5800000-0000-0000-0000-000000000002';
insert into public.orders(id,user_id,status,total,stripe_payment_intent_id) values
('f5810000-0000-0000-0000-000000000001','f5800000-0000-0000-0000-000000000001','paid',20,'pi_refund_fixture');
select public.record_verified_refund('f5810000-0000-0000-0000-000000000001','pi_refund_fixture','re_first',2000,'sgd','pending',now(),null);
do $$ begin
 if not exists(select 1 from public.orders where id='f5810000-0000-0000-0000-000000000001' and status='paid' and refund_status='pending' and refund_amount=0 and refund_pending_amount=20 and refunded_at is null) then
  raise exception 'Pending refund was incorrectly completed';
 end if;
end $$;
select public.record_verified_refund('f5810000-0000-0000-0000-000000000001','pi_refund_fixture','re_first',2000,'sgd','failed',now(),'insufficient_funds');
do $$ begin
 if not exists(select 1 from public.orders where id='f5810000-0000-0000-0000-000000000001' and status='paid' and refund_status='failed' and refund_amount=0 and refunded_at is null) then
  raise exception 'Failed refund was incorrectly completed';
 end if;
end $$;
-- Stale deliveries cannot overwrite a terminal failure.
select public.record_verified_refund('f5810000-0000-0000-0000-000000000001','pi_refund_fixture','re_first',2000,'sgd','pending',now(),null,'2020-01-01'::timestamptz);
select public.record_verified_refund('f5810000-0000-0000-0000-000000000001','pi_refund_fixture','re_partial',500,'sgd','succeeded',now(),null);
do $$ begin
 if not exists(select 1 from public.orders where id='f5810000-0000-0000-0000-000000000001' and status='paid' and refund_status='partially_refunded' and refund_amount=5 and refunded_at is null) then
  raise exception 'Partial refund changed fulfillment status or amount';
 end if;
end $$;
select public.record_verified_refund('f5810000-0000-0000-0000-000000000001','pi_refund_fixture','re_rest',1500,'sgd','succeeded',now(),null);
-- Duplicate/stale delivery cannot double-count or undo success.
select public.record_verified_refund('f5810000-0000-0000-0000-000000000001','pi_refund_fixture','re_rest',1500,'sgd','pending',now(),null,'2020-01-01'::timestamptz);
do $$ begin
 if not exists(select 1 from public.orders where id='f5810000-0000-0000-0000-000000000001' and status='refunded' and refund_status='succeeded' and refund_amount=20 and refund_pending_amount=0 and refunded_at is not null) then
  raise exception 'Full refund aggregate incorrect';
 end if;
 if (select count(*) from public.order_status_history where order_id='f5810000-0000-0000-0000-000000000001' and to_status='refunded') <> 1 then raise exception 'Refund transition duplicated'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','f5800000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$ declare rejected boolean := false; begin
 begin update public.orders set refund_status='pending' where id='f5810000-0000-0000-0000-000000000001'; exception when raise_exception then rejected:=true; end;
 if not rejected then raise exception 'Admin forged refund state'; end if;
 if has_function_privilege(current_user,'public.record_verified_refund(uuid,text,text,bigint,text,text,timestamptz,text,timestamptz)','execute') then raise exception 'Admin can call verified-refund RPC'; end if;
end $$;
reset role;
-- A later bank return can change succeeded to failed. Keep actual money
-- accurate without silently reopening a terminal fulfillment/inventory state.
set local role service_role;
select public.record_verified_refund('f5810000-0000-0000-0000-000000000001','pi_refund_fixture','re_rest',1500,'sgd','failed',now(),'declined');
reset role;
do $$ begin
 if not exists(select 1 from public.orders where id='f5810000-0000-0000-0000-000000000001' and refund_status='partially_refunded' and refund_amount=5 and refunded_at is null) then
  raise exception 'Later bank return did not correct the financial summary';
 end if;
end $$;
select 'Verified asynchronous/partial refund checks passed';
rollback;
