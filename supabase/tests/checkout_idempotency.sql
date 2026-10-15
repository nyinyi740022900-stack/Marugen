-- A retry key identifies the whole checkout attempt, including paid/refunded
-- orders. Only a verified cancelled attempt may release the key for reuse.
\set ON_ERROR_STOP on
begin;
create function pg_temp.expect_duplicate_checkout(statement text) returns void
language plpgsql as $$
declare rejected boolean := false;
begin
  begin execute statement;
  exception when unique_violation then rejected := true; end;
  if not rejected then raise exception 'Checkout retry created a second order: %', statement; end if;
end;
$$;
insert into auth.users(id,email) values
('90000000-0000-0000-0000-000000000001','idempotency@example.invalid');
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim.role','service_role',true);
insert into public.orders(id,user_id,status,idempotency_key,stripe_payment_intent_id) values
('91000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','pending','same-attempt','pi_idempotency_paid');
update public.orders set status='paid' where id='91000000-0000-0000-0000-000000000001';
select pg_temp.expect_duplicate_checkout($$insert into public.orders(user_id,idempotency_key) values ('90000000-0000-0000-0000-000000000001','same-attempt')$$);
update public.orders set status='refunded' where id='91000000-0000-0000-0000-000000000001';
select pg_temp.expect_duplicate_checkout($$insert into public.orders(user_id,idempotency_key) values ('90000000-0000-0000-0000-000000000001','same-attempt')$$);
insert into public.orders(id,user_id,status,idempotency_key,stripe_payment_intent_id) values
('91000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-000000000001','pending','cancelled-attempt','pi_idempotency_cancel');
-- A backend write after external verification releases the cancelled key.
update public.orders set status='cancelled' where id='91000000-0000-0000-0000-000000000002';
insert into public.orders(user_id,idempotency_key) values ('90000000-0000-0000-0000-000000000001','cancelled-attempt');
select pg_temp.expect_duplicate_checkout($$insert into public.orders(user_id,idempotency_key) values ('90000000-0000-0000-0000-000000000001','cancelled-attempt')$$);
-- Legacy requests without a retry key remain supported.
insert into public.orders(user_id) values ('90000000-0000-0000-0000-000000000001'),('90000000-0000-0000-0000-000000000001');
reset role;
select 'Checkout idempotency integration checks passed' as result;
rollback;
