\set ON_ERROR_STOP on
\ir ../migrations/0062_order_parcels.sql
\ir ../migrations/0063_tracking_progress_guards.sql
\ir ../migrations/0064_tracking_return_after_custody.sql
create function pg_temp.reject_write(statement text) returns void language plpgsql as $$ declare rejected boolean:=false; begin begin execute statement; exception when others then rejected:=true; end; if not rejected then raise exception 'Expected parcel write rejection: %',statement; end if; end $$;
-- Fixtures committed by the shipping finance test before this suite.
insert into public.order_items(order_id,product_id,variant_id,product_name,product_category,quantity,unit_price) select 'd5820000-0000-0000-0000-000000000001',product_id,id,'Test food','fish_food',2,5 from public.product_variants where label='500g';
update public.orders set status='paid' where id='d5820000-0000-0000-0000-000000000001';
create temp table parcel_fixture as select id::text item_id,order_id from public.order_items where order_id='d5820000-0000-0000-0000-000000000001';
create function pg_temp.box(i text,n integer default 1) returns jsonb language sql as $$ select jsonb_build_object('items',jsonb_build_array(jsonb_build_object('order_item_id',i,'quantity',n)),'weight_kg',1,'length_cm',10,'width_cm',10,'height_cm',10,'collection_date','2099-01-01') $$;
select pg_temp.reject_write(format('select public.save_order_parcel_plan(%L,%L::jsonb)',order_id,jsonb_build_array(pg_temp.box(item_id,2),pg_temp.box(item_id)))) from parcel_fixture;
select pg_temp.reject_write(format('select public.save_order_parcel_plan(%L,%L::jsonb)',order_id,jsonb_build_array(pg_temp.box(item_id)))) from parcel_fixture;
select pg_temp.reject_write(format('select public.save_order_parcel_plan(%L,%L::jsonb)',order_id,jsonb_build_array(pg_temp.box(item_id),pg_temp.box('00000000-0000-0000-0000-000000000000')))) from parcel_fixture;
select pg_temp.reject_write(format('select public.save_order_parcel_plan(%L,%L::jsonb)',order_id,jsonb_build_array(pg_temp.box(item_id),jsonb_set(pg_temp.box(item_id),'{items}','[]')))) from parcel_fixture;
select pg_temp.reject_write(format('select public.save_order_parcel_plan(%L,%L::jsonb)',order_id,jsonb_build_array(pg_temp.box(item_id),jsonb_set(pg_temp.box(item_id),'{length_cm}','0')))) from parcel_fixture;
select pg_temp.reject_write(format('select public.save_order_parcel_plan(%L,%L::jsonb)',order_id,jsonb_build_array(pg_temp.box(item_id),jsonb_set(pg_temp.box(item_id),'{collection_date}','"2000-01-01"')))) from parcel_fixture;
select public.save_order_parcel_plan(order_id,jsonb_build_array(pg_temp.box(item_id),pg_temp.box(item_id))) from parcel_fixture;
do $$ begin
 if public.claim_courier_shipment('d5820000-0000-0000-0000-000000000001','easyparcel') then raise exception 'Legacy claim stole split plan';end if;
end $$;
select pg_temp.reject_write($$select public.claim_order_parcel_plan('d5820000-0000-0000-0000-000000000001','stale',100)$$);
select public.quote_order_parcel_plan('d5820000-0000-0000-0000-000000000001',(select jsonb_agg(jsonb_build_object('id',id,'service_id','single','carrier_name','Carrier','quoted_total_cents',500)) from public.order_parcels),'sig',now()+interval '10 minutes');
select pg_temp.reject_write($$select public.claim_order_parcel_plan('d5820000-0000-0000-0000-000000000001','sig',999)$$);
update public.order_parcels set quote_expires_at=now()-interval '1 second';
select pg_temp.reject_write($$select public.claim_order_parcel_plan('d5820000-0000-0000-0000-000000000001','sig',1000)$$);
update public.order_parcels set quote_expires_at=now()+interval '10 minutes';
set role service_role;
select public.claim_order_parcel_plan('d5820000-0000-0000-0000-000000000001','sig',1000);
reset role;
select pg_temp.reject_write($$select public.claim_order_parcel_plan('d5820000-0000-0000-0000-000000000001','sig',1000)$$);
select pg_temp.reject_write(format('select public.save_order_parcel_plan(%L,%L::jsonb)',order_id,jsonb_build_array(pg_temp.box(item_id),pg_temp.box(item_id)))) from parcel_fixture;
do $$ begin
 if (select buyer_shipping_cents from public.orders where id='d5820000-0000-0000-0000-000000000001')<>202 then raise exception 'Buyer repriced';end if;
end $$;
set role authenticated;
select pg_temp.reject_write($$select public.save_order_parcel_plan('d5820000-0000-0000-0000-000000000001','[]')$$);
select pg_temp.reject_write($$update public.order_parcels set state='delivered'$$);
reset role;
-- Provider updates aggregate across every actual box.
update public.order_parcels set state='booked',tracking_number='AWB'||parcel_number,shipment_number='SHIP'||parcel_number;
select public.apply_order_parcel_tracking(id,'AWB'||parcel_number,'SHIP'||parcel_number,5,'Delivered') from public.order_parcels where parcel_number=1;
do $$ begin if (select status from public.orders where id='d5820000-0000-0000-0000-000000000001')='delivered' then raise exception 'Partial delivery completed order';end if;end $$;
select 'order parcel boundary checks passed';
-- Strict identity match: webhook hints cannot relabel a parcel.
select pg_temp.reject_write(format('select public.apply_order_parcel_tracking(%L,%L,%L,5,%L)',id,'WRONG','SHIP'||parcel_number,'Delivered')) from public.order_parcels where parcel_number=2;
-- Buyer can read only own parcels, other buyers see none; neither can write.
set role authenticated;
select set_config('request.jwt.claim.sub','d5800000-0000-0000-0000-000000000001',false);
do $$ begin if(select count(*) from public.order_parcels)<>2 then raise exception 'Buyer cannot read own boxes';end if;end $$;
select set_config('request.jwt.claim.sub','d5800000-0000-0000-0000-000000000099',false);
do $$ begin if exists(select 1 from public.order_parcels)then raise exception 'Other buyer can read boxes';end if;end $$;
reset role;
select set_config('request.jwt.claim.sub','',false);
-- Manual parent completion is also forbidden while any actual box is pending.
select pg_temp.reject_write($$update public.orders set status='delivered' where id='d5820000-0000-0000-0000-000000000001'$$);
-- Paid-in-provider recovery attaches a real AWB only to the same shipment.
update public.order_parcels set tracking_number=null,state='payment_required' where parcel_number=2;
select pg_temp.reject_write(format('select public.recover_order_parcel_identity(%L,%L,%L,%L)',id,'WRONG','AWB2','https://label')) from public.order_parcels where parcel_number=2;
select pg_temp.reject_write(format('select public.recover_order_parcel_identity(%L,%L,%L,%L)',id,'SHIP2','EPSAMPLE2','https://label')) from public.order_parcels where parcel_number=2;
select public.recover_order_parcel_identity(id,'SHIP2','AWB2','https://label') from public.order_parcels where parcel_number=2;
-- Refreshes must not erase authenticated collection/transit evidence.
select public.apply_order_parcel_tracking(id,'AWB2','SHIP2',3,'Collected') from public.order_parcels where parcel_number=2;
select public.apply_order_parcel_tracking(id,'AWB2','SHIP2',7,'Scheduled') from public.order_parcels where parcel_number=2;
do $$ begin if exists(select 1 from public.order_parcels where parcel_number=2 and (state<>'collected' or tracking_status_code<>3 or tracking_status<>'Collected'))then raise exception 'Scheduled refresh erased collection evidence';end if;end $$;
select public.apply_order_parcel_tracking(id,'AWB2','SHIP2',4,'Delivery In Transit') from public.order_parcels where parcel_number=2;
select public.apply_order_parcel_tracking(id,'AWB2','SHIP2',3,'Collected') from public.order_parcels where parcel_number=2;
select public.apply_order_parcel_tracking(id,'AWB2','SHIP2',null,'Unknown') from public.order_parcels where parcel_number=2;
do $$ begin if exists(select 1 from public.order_parcels where parcel_number=2 and (state<>'in_transit' or tracking_status_code<>4))then raise exception 'Delayed/unknown refresh erased transit evidence';end if;end $$;
-- Entire order becomes delivered only after the last box.
select public.apply_order_parcel_tracking(id,'AWB'||parcel_number,'SHIP'||parcel_number,5,'Delivered') from public.order_parcels where parcel_number=2;
do $$ begin if(select status from public.orders where id='d5820000-0000-0000-0000-000000000001')<>'delivered' then raise exception 'All boxes delivered did not complete order';end if;end $$;

-- Delayed provider events cannot regress a delivered parcel.
select public.apply_order_parcel_tracking(id,'AWB'||parcel_number,'SHIP'||parcel_number,7,'Scheduled') from public.order_parcels where parcel_number=1;
do $$ begin if exists(select 1 from public.order_parcels where state<>'delivered')then raise exception 'Stale event regressed delivered parcel';end if;end $$;

do $$ begin if exists(select 1 from public.order_parcels where tracking_status_code<>5 or tracking_status<>'Delivered')then raise exception 'Delivered metadata regressed despite delivered parcel state';end if;end $$;
