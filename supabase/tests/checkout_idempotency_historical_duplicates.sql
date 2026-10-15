-- Runner invokes with -v setup=true before 0054, then setup=false after the
-- expected migration failure. Committed fixtures prove data is preserved.
\set ON_ERROR_STOP on
\if :setup
insert into auth.users(id,email) values ('92000000-0000-0000-0000-000000000001','duplicate-history@example.invalid');
insert into public.orders(id,user_id,status,idempotency_key) values
('92000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001','paid','historical-duplicate'),
('92000000-0000-0000-0000-000000000003','92000000-0000-0000-0000-000000000001','pending','historical-duplicate');
\else
do $$ begin
  if (select count(*) from public.orders where user_id='92000000-0000-0000-0000-000000000001' and idempotency_key='historical-duplicate') <> 2
     or (select status from public.orders where id='92000000-0000-0000-0000-000000000002') <> 'paid'
     or (select status from public.orders where id='92000000-0000-0000-0000-000000000003') <> 'pending' then
    raise exception 'Migration silently altered historical duplicate orders';
  end if;
  if to_regclass('public.orders_user_pending_idempotency_key_uidx') is null then
    raise exception 'Failed migration removed existing pending checkout protection';
  end if;
end $$;
delete from public.orders where user_id='92000000-0000-0000-0000-000000000001';
delete from auth.users where id='92000000-0000-0000-0000-000000000001';
select 'Historical duplicate orders preserved after migration rejection' as result;
\endif
