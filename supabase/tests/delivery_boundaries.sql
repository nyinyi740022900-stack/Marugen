-- Disposable PostgreSQL regression: backfill, protected snapshots and atomic claims.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values
('d5700000-0000-0000-0000-000000000001','delivery-buyer@example.invalid'),
('d5700000-0000-0000-0000-000000000002','delivery-owner@example.invalid');
update public.profiles set role='owner' where id='d5700000-0000-0000-0000-000000000002';
insert into public.products(id,name,category,price,stock_quantity,show_price) values
('d5710000-0000-0000-0000-000000000001','Food','fish_food',10,20,true),
('d5710000-0000-0000-0000-000000000002','Fish','koi',100,1,true);
insert into public.orders(id,user_id,total) values
('d5720000-0000-0000-0000-000000000001','d5700000-0000-0000-0000-000000000001',10),
('d5720000-0000-0000-0000-000000000002','d5700000-0000-0000-0000-000000000001',110),
('d5720000-0000-0000-0000-000000000003','d5700000-0000-0000-0000-000000000001',10),
('d5720000-0000-0000-0000-000000000004','d5700000-0000-0000-0000-000000000001',10),
('d5720000-0000-0000-0000-000000000005','d5700000-0000-0000-0000-000000000001',10);
insert into public.order_items(order_id,product_id,product_name,quantity,unit_price) values
('d5720000-0000-0000-0000-000000000001','d5710000-0000-0000-0000-000000000001','Food',1,10),
('d5720000-0000-0000-0000-000000000002','d5710000-0000-0000-0000-000000000001','Food',1,10),
('d5720000-0000-0000-0000-000000000002','d5710000-0000-0000-0000-000000000002','Fish',1,100),
('d5720000-0000-0000-0000-000000000003',null,'Deleted unknown',1,10),
('d5720000-0000-0000-0000-000000000005','d5710000-0000-0000-0000-000000000001','Food',1,10);
-- Before migration: historical known snapshots backfilled, detached stays unknown.
\ir ../migrations/0057_delivery_fulfillment.sql
create function pg_temp.check_true(value boolean, message text) returns void language plpgsql as $$ begin if value is distinct from true then raise exception '%',message; end if; end $$;
select pg_temp.check_true((select fulfillment_method='courier' from public.orders where id='d5720000-0000-0000-0000-000000000001'),'Food backfill');
select pg_temp.check_true((select fulfillment_method='shop_delivery' from public.orders where id='d5720000-0000-0000-0000-000000000002'),'Mixed basket backfill');
select pg_temp.check_true((select fulfillment_method='review_required' from public.orders where id='d5720000-0000-0000-0000-000000000003'),'Unknown backfill');
select pg_temp.check_true(not public.claim_courier_shipment('d5720000-0000-0000-0000-000000000001','easyparcel'),'Pending cannot be booked');
update public.orders set status='paid' where id in ('d5720000-0000-0000-0000-000000000001','d5720000-0000-0000-0000-000000000002','d5720000-0000-0000-0000-000000000003');
select pg_temp.check_true(not public.claim_courier_shipment('d5720000-0000-0000-0000-000000000002','easyparcel'),'Mixed cannot be booked');
select pg_temp.check_true(not public.claim_courier_shipment('d5720000-0000-0000-0000-000000000003','easyparcel'),'Unknown cannot be booked');
select pg_temp.check_true(public.claim_courier_shipment('d5720000-0000-0000-0000-000000000001','easyparcel'),'Paid food claim');
select pg_temp.check_true(not public.claim_courier_shipment('d5720000-0000-0000-0000-000000000001','easyparcel'),'Double claim blocked');
select pg_temp.check_true(not public.claim_courier_shipment('d5720000-0000-0000-0000-000000000001','seventeentrack'),'Provider overwrite blocked');
select pg_temp.check_true((select status='paid' and tracking_registered and easyparcel_booking_state='booking' from public.orders where id='d5720000-0000-0000-0000-000000000001'),'Claim does not ship');
update public.orders set status='paid' where id='d5720000-0000-0000-0000-000000000005';
select pg_temp.check_true(public.claim_courier_shipment('d5720000-0000-0000-0000-000000000005','seventeentrack','MANUAL123'),'Manual claim can save confirmed handover');
select pg_temp.check_true((select qxpress_tracking_no='MANUAL123' and tracking_provider='seventeentrack' and status='shipped' from public.orders where id='d5720000-0000-0000-0000-000000000005'),'Manual candidate and shipped state persist atomically');
-- Product deletion preserves category snapshot and courier routing.
delete from public.products where id='d5710000-0000-0000-0000-000000000001';
select pg_temp.check_true((select product_id is null and product_category='fish_food' from public.order_items where order_id='d5720000-0000-0000-0000-000000000001'),'Deleted snapshot survives');
update public.orders set status='paid' where id='d5720000-0000-0000-0000-000000000004';
update public.orders set status='shipped' where id='d5720000-0000-0000-0000-000000000004';
create function pg_temp.reject_delivery_write(statement text) returns void language plpgsql as $$ declare rejected boolean:=false; begin begin execute statement; exception when raise_exception or insufficient_privilege then rejected:=true; end; if not rejected then raise exception 'Expected delivery write rejection: %',statement; end if; end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','d5700000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claim.role','authenticated',true);
select pg_temp.reject_delivery_write($$update public.orders set fulfillment_method='courier' where id='d5720000-0000-0000-0000-000000000002'$$);
select pg_temp.reject_delivery_write($$update public.orders set tracking_registered=false where id='d5720000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_delivery_write($$select public.claim_courier_shipment('d5720000-0000-0000-0000-000000000004','easyparcel')$$);
select pg_temp.check_true(public.confirm_shop_delivery('d5720000-0000-0000-0000-000000000004'),'Legacy shipped order with no claim may use shop fallback');
select pg_temp.check_true(public.confirm_shop_delivery('d5720000-0000-0000-0000-000000000003'),'Admin may choose safe shop delivery for an unknown historical basket');
select pg_temp.check_true(not public.confirm_shop_delivery('d5720000-0000-0000-0000-000000000001'),'Cannot erase active courier booking with shop fallback');
reset role;
select pg_temp.check_true((select fulfillment_method='shop_delivery' from public.orders where id='d5720000-0000-0000-0000-000000000003'),'Safe shop fallback saved');
select 'delivery boundary checks passed';
rollback;
