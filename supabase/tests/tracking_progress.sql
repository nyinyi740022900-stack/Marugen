\set ON_ERROR_STOP on
-- Returns are an exception after verified custody, not a loss of progress.
do $$ declare prior_code integer; begin
 foreach prior_code in array array[3,4] loop
 if not public.accept_easyparcel_tracking(prior_code,2::smallint,6,'Returned',
   '2026-10-24 01:00Z','2026-10-24 02:00Z',
   '2026-10-24 01:00Z','2026-10-24 02:00Z') then
  raise exception 'Fresh return after transit was rejected';
 end if;
 end loop;
 if public.accept_easyparcel_tracking(6,2::smallint,4,'In Transit',
   '2026-10-24 02:00Z','2026-10-24 03:00Z',
   '2026-10-24 02:00Z','2026-10-24 03:00Z') then
  raise exception 'Returned terminal state regressed';
 end if;
end $$;
create function pg_temp.reject_write(statement text) returns void language plpgsql as $$ declare rejected boolean:=false; begin begin execute statement; exception when others then rejected:=true; end; if not rejected then raise exception 'Expected tracking write rejection: %',statement; end if; end $$;
-- Dedicated existing single-shipment fixture (packing, with a claimed booking).
update public.orders set qxpress_tracking_no='LEGACYAWB',easyparcel_shipment_id='LEGACYSHIP' where id='d5820000-0000-0000-0000-000000000002';
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',5,'Waiting Payment',null,'2026-10-24 01:00Z');
do $$ begin if exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and status='delivered')then raise exception 'Unpaid evidence falsely delivered an order';end if;end $$;
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',null,'Delivered',null,'2026-10-24 01:00Z');
do $$ begin if exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and status<>'packing')then raise exception 'Unknown code promoted order';end if;end $$;
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',3,'Collected','Depot','2026-10-24 02:00Z');
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',7,'Scheduled',null,'2026-10-24 03:00Z');
do $$ begin if not exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and status='shipped' and tracking_status_code=3 and tracking_status='Collected' and tracking_status_detail='Depot' and tracking_observed_at='2026-10-24 02:00Z')then raise exception 'Scheduling refresh erased collection';end if;end $$;
-- An earlier-started request completing late must not promote or overwrite.
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',5,'Delivered',null,'2026-10-24 01:00Z');
do $$ begin if exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and status='delivered')then raise exception 'Older snapshot promoted order';end if;end $$;
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',4,'In Transit','Hub','2026-10-24 04:00Z');
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',8,'On Hold','Hub','2026-10-24 05:00Z');
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',7,'Scheduled',null,'2026-10-24 06:00Z');
do $$ begin if not exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and tracking_status_code=8 and tracking_progress=2)then raise exception 'Hold erased transit watermark';end if;end $$;
-- Older direct writer is also guarded during rolling deployment.
update public.orders set tracking_status_code=7,tracking_status='Scheduled',tracking_status_detail='stale',tracking_updated_at=now() where id='d5820000-0000-0000-0000-000000000002';
do $$ begin if exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and tracking_status_code<>8)then raise exception 'Direct writer erased custody';end if;end $$;
-- Verify the full atomic path, then restore the fixture for later checks.
begin;
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',6,'Returned','Shop','2026-10-24 07:00Z');
do $$ begin if not exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and status='shipped' and tracking_status_code=6 and tracking_progress=2)then raise exception 'Return did not retain custody without delivering';end if;end $$;
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',4,'In Transit','Hub','2026-10-24 08:00Z');
do $$ begin if not exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and tracking_status_code=6 and tracking_progress=2)then raise exception 'Terminal return regressed';end if;end $$;
rollback;
select pg_temp.reject_write($$select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','OTHER',5,'Delivered',null,now())$$);
update public.profiles set role='owner' where id='d5800000-0000-0000-0000-000000000001';
set role authenticated;
select set_config('request.jwt.claim.sub','d5800000-0000-0000-0000-000000000001',false);
select pg_temp.reject_write($$update public.orders set tracking_progress=0 where id='d5820000-0000-0000-0000-000000000002'$$);
select pg_temp.reject_write($$update public.orders set tracking_observed_at=now()+interval '1 day' where id='d5820000-0000-0000-0000-000000000002'$$);
select pg_temp.reject_write($$update public.orders set tracking_event_at=now()+interval '1 day' where id='d5820000-0000-0000-0000-000000000002'$$);
select pg_temp.reject_write($$select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',5,'Delivered',null,now())$$);
reset role;
-- A fresh poll may still contain older provider event evidence. Request time
-- alone must not let this replace a later hold event or falsely deliver.
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',8,'On Hold','Hub','2026-10-24 06:00Z','2026-10-24 05:00Z');
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',5,'Delivered',null,'2026-10-24 06:30Z','2026-10-24 04:00Z');
do $$ begin if exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and (status='delivered' or tracking_status_code<>8 or tracking_event_at<>'2026-10-24 05:00Z'))then raise exception 'New poll with old provider event erased hold';end if;end $$;
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',5,'Delivered',null,'2026-10-24 07:00Z','2026-10-24 06:00Z');
select public.apply_easyparcel_order_tracking('d5820000-0000-0000-0000-000000000002','LEGACYAWB','LEGACYSHIP',4,'In Transit',null,'2026-10-24 08:00Z');
do $$ begin if not exists(select 1 from public.orders where id='d5820000-0000-0000-0000-000000000002' and status='delivered' and tracking_status_code=5 and tracking_status='Delivered')then raise exception 'Delivered metadata regressed';end if;end $$;
select 'Single-shipment tracking progression checks passed';
