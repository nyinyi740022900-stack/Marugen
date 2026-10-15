-- Run with psql after applying migrations. All fixtures are rolled back.
-- Assertions exercise real RLS and stock/review triggers, with Supabase roles.
\set ON_ERROR_STOP on
begin;
create temporary table boundary_results (label text, passed boolean);
grant all on boundary_results to authenticated, service_role, anon;
create function pg_temp.check_boundary(label text, passed boolean) returns void
language sql as $$ insert into boundary_results values (label, coalesce(passed, false)); $$;
create function pg_temp.reject_boundary(label text, statement text, expected_state text)
returns void language plpgsql as $$
declare rejected boolean := false;
begin
  begin
    execute statement;
  exception when others then
    rejected := sqlstate = expected_state;
    if not rejected then raise; end if;
  end;
  perform pg_temp.check_boundary(label, rejected);
end;
$$;
insert into auth.users(id, email) values
('10000000-0000-0000-0000-000000000001', 'boundary-customer@example.invalid'),
('10000000-0000-0000-0000-000000000002', 'boundary-admin@example.invalid');
update public.profiles set role='owner' where id='10000000-0000-0000-0000-000000000002';
insert into public.products(id,name,category,stock_quantity,price,size_options) values
('20000000-0000-0000-0000-000000000001','Boundary food','fish_food',10,10,'{}'),
('20000000-0000-0000-0000-000000000002','Boundary sized food','fish_food',10,10,array['S','L']),
('20000000-0000-0000-0000-000000000003','Boundary koi','koi',1,10,'{}'),
('20000000-0000-0000-0000-000000000004','Boundary variant koi','koi',0,10,'{}');
insert into public.product_variants(id,product_id,label,price,stock_quantity) values
('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','1kg',10,10),
('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','1kg',10,10),
('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000004','Individual koi',10,10);
insert into public.product_variant_size_stocks(variant_id,size_label,stock_quantity) values
('30000000-0000-0000-0000-000000000002','S',10),
('30000000-0000-0000-0000-000000000002','L',10);
insert into public.orders(id,user_id,status) values
('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','pending'),
('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','pending');
-- A verified purchase for later review inserts.
insert into public.order_items(order_id,product_id,variant_id,product_name,quantity) values
('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Boundary food',1);
update public.orders set status='paid' where id='40000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select pg_temp.reject_boundary('customer cannot create pending order',
  $$insert into public.orders(user_id) values ('10000000-0000-0000-0000-000000000001')$$,'42501');
select pg_temp.reject_boundary('customer cannot reserve stock in existing order',
  $$insert into public.order_items(order_id,product_id,variant_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Boundary food',1)$$,'42501');
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim.role','service_role',true);
select pg_temp.reject_boundary('negative quantity cannot inflate stock',
  $$insert into public.order_items(order_id,product_id,variant_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Boundary food',-2)$$,'23514');
select pg_temp.reject_boundary('zero quantity rejected',
  $$insert into public.order_items(order_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','Detached snapshot',0)$$,'23514');
select pg_temp.reject_boundary('variant must belong to product',
  $$insert into public.order_items(order_id,product_id,variant_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000001','Wrong variant',1)$$,'23514');
select pg_temp.reject_boundary('live fish quantity limited to one',
  $$insert into public.order_items(order_id,product_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','Boundary koi',2)$$,'23514');
select pg_temp.reject_boundary('variant live fish quantity limited to one',
  $$insert into public.order_items(order_id,product_id,variant_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000003','Variant koi',2)$$,'23514');
select pg_temp.reject_boundary('variant product cannot bypass variant stock',
  $$insert into public.order_items(order_id,product_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Missing variant',1)$$,'23514');
select pg_temp.reject_boundary('invalid product size rejected',
  $$insert into public.order_items(order_id,product_id,variant_id,size_label,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','bogus','Invalid size',1)$$,'23514');
select pg_temp.reject_boundary('missing size selection rejected',
  $$insert into public.order_items(order_id,product_id,variant_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','Missing size',1)$$,'23514');
select pg_temp.reject_boundary('variant without product rejected',
  $$insert into public.order_items(order_id,variant_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Detached variant',1)$$,'23514');
-- A configured product size must have a matching inventory matrix cell.
delete from public.product_variant_size_stocks where variant_id='30000000-0000-0000-0000-000000000002' and size_label='L';
select pg_temp.reject_boundary('missing size matrix cell cannot use variant stock',
  $$insert into public.order_items(order_id,product_id,variant_id,size_label,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','L','Missing cell',1)$$,'23514');
-- Valid reservation and oversell demonstrate the atomic conditional update.
insert into public.order_items(id,order_id,product_id,variant_id,size_label,product_name,quantity) values
('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','S','Sized food',3);
select pg_temp.reject_boundary('quantity constraint protects updates',
  $$update public.order_items set quantity=-1 where id='50000000-0000-0000-0000-000000000001'$$,'23514');
select pg_temp.check_boundary('valid size reservation decrements stock',
  (select stock_quantity=7 from public.product_variant_size_stocks where variant_id='30000000-0000-0000-0000-000000000002' and size_label='S'));
select pg_temp.reject_boundary('oversell rejected atomically',
  $$insert into public.order_items(order_id,product_id,variant_id,size_label,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','S','Sized food',8)$$,'P0001');
update public.orders set status='cancelled' where id='40000000-0000-0000-0000-000000000001';
select pg_temp.check_boundary('cancel restores exact size stock',
  (select stock_quantity=10 from public.product_variant_size_stocks where variant_id='30000000-0000-0000-0000-000000000002' and size_label='S'));
update public.orders set status='cancelled' where id='40000000-0000-0000-0000-000000000001';
select pg_temp.check_boundary('repeat cancel cannot restore twice',
  (select stock_quantity=10 from public.product_variant_size_stocks where variant_id='30000000-0000-0000-0000-000000000002' and size_label='S'));
-- The order can be cancelled before any item exists. Late inserts must
-- neither reserve stock nor create lines the cancellation never restored.
select pg_temp.reject_boundary('cancelled parent rejects late reservation',
  $$insert into public.order_items(order_id,product_id,variant_id,product_name,quantity) values
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Late food',2)$$,'P0001');
select pg_temp.check_boundary('late reservation leaves stock unchanged',
  (select stock_quantity=9 from public.product_variants where id='30000000-0000-0000-0000-000000000001'));
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
insert into public.product_reviews(id,product_id,user_id,rating,comment,is_hidden,admin_reply,admin_reply_at) values
('60000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',4,'Original',true,'Forged shop reply',now());
select pg_temp.check_boundary('customer review insert cannot forge admin fields',
  (select not is_hidden and admin_reply is null and admin_reply_at is null from public.product_reviews where id='60000000-0000-0000-0000-000000000001'));
-- Real admin moderation, followed by a customer content edit with forged fields.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
update public.product_reviews set is_hidden=true,admin_reply='Real shop reply',admin_reply_at='2026-01-01Z' where id='60000000-0000-0000-0000-000000000001';
select pg_temp.check_boundary('admin can moderate and reply',
  (select is_hidden and admin_reply='Real shop reply' and admin_reply_at='2026-01-01Z'::timestamptz from public.product_reviews where id='60000000-0000-0000-0000-000000000001'));
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
update public.product_reviews set rating=5,comment='Edited',is_hidden=false,admin_reply=null,admin_reply_at=null where id='60000000-0000-0000-0000-000000000001';
select pg_temp.check_boundary('customer content edit preserves moderation and reply',
  (select rating=5 and comment='Edited' and is_hidden and admin_reply='Real shop reply' and admin_reply_at='2026-01-01Z'::timestamptz from public.product_reviews where id='60000000-0000-0000-0000-000000000001'));
reset role;
set local role service_role;
-- Service writes with a user subject must still be recognized explicitly.
select set_config('request.jwt.claim.role','service_role',true);
update public.product_reviews set is_hidden=false,admin_reply='Backend reply' where id='60000000-0000-0000-0000-000000000001';
select pg_temp.check_boundary('service role can legitimately moderate',
  (select not is_hidden and admin_reply='Backend reply' from public.product_reviews where id='60000000-0000-0000-0000-000000000001'));
reset role;
table boundary_results;
do $$ declare failures text; begin
  select string_agg(label, ', ') into failures from boundary_results where not passed;
  if failures is not null then raise exception 'Boundary regressions: %', failures; end if;
end $$;
rollback;
