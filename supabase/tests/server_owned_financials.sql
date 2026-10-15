-- Disposable PostgreSQL integration regression: authenticated admin != backend.
\set ON_ERROR_STOP on
begin;
create function pg_temp.reject_financial_write(statement text) returns void
language plpgsql as $$
declare rejected boolean := false;
begin
  begin execute statement;
  exception when raise_exception then rejected := true; end;
  if not rejected then raise exception 'Expected financial write rejection: %', statement; end if;
end;
$$;
insert into auth.users(id,email) values
('d5500000-0000-0000-0000-000000000001','financial-buyer@example.invalid'),
('d5500000-0000-0000-0000-000000000002','financial-owner@example.invalid');
update public.profiles set role='owner' where id='d5500000-0000-0000-0000-000000000002';
insert into public.orders(id,user_id,total,idempotency_key) values
('d5510000-0000-0000-0000-000000000001','d5500000-0000-0000-0000-000000000001',10,'financial-key');
set local role authenticated;
select set_config('request.jwt.claim.sub','d5500000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claim.role','authenticated',true);
select pg_temp.reject_financial_write($$update public.orders set status='paid' where id='d5510000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_financial_write($$update public.orders set total=0.01 where id='d5510000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_financial_write($$update public.orders set user_id='d5500000-0000-0000-0000-000000000002' where id='d5510000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_financial_write($$update public.orders set idempotency_key=null where id='d5510000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_financial_write($$update public.orders set stripe_refund_id='fake' where id='d5510000-0000-0000-0000-000000000001'$$);
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
update public.orders set status='paid' where id='d5510000-0000-0000-0000-000000000001';
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d5500000-0000-0000-0000-000000000002',true);
select pg_temp.reject_financial_write($$update public.orders set status='refunded',refund_amount=10,refunded_at=now() where id='d5510000-0000-0000-0000-000000000001'$$);
update public.orders set status='packing' where id='d5510000-0000-0000-0000-000000000001';
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
update public.orders set status='refunded',stripe_refund_id='re_verified_fixture',refund_amount=10,refunded_at=now()
where id='d5510000-0000-0000-0000-000000000001';
reset role;
do $$ begin
 if not exists(select 1 from public.orders where id='d5510000-0000-0000-0000-000000000001' and status='refunded' and refund_amount=10) then
  raise exception 'Verified backend update did not succeed';
 end if;
end $$;
select 'server-owned financial authority checks passed';
rollback;
