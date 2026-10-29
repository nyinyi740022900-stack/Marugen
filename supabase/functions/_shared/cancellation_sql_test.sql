\set ON_ERROR_STOP on
do $$ begin if to_regclass('public.order_cancellation_requests') is null then raise exception 'Cancellation request feature is missing';end if;end $$;
begin;
insert into auth.users(id,email) values
 ('c6600000-0000-0000-0000-000000000001','cancel-buyer@example.invalid'),
 ('c6600000-0000-0000-0000-000000000002','cancel-owner@example.invalid'),
 ('c6600000-0000-0000-0000-000000000003','cancel-other@example.invalid');
update public.profiles set role='owner' where id='c6600000-0000-0000-0000-000000000002';
insert into public.orders(id,user_id,status,total,stripe_payment_intent_id) select
 ('c6610000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'c6600000-0000-0000-0000-000000000001','paid',20,'pi_cancel_'||n from generate_series(1,8)n;
create function pg_temp.reject_write(statement text) returns void language plpgsql as $$ declare rejected boolean:=false;begin begin execute statement;exception when others then rejected:=true;end;if not rejected then raise exception 'Expected cancellation rejection: %',statement;end if;end $$;
select pg_temp.reject_write($$select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000001','c6600000-0000-0000-0000-000000000003','request','Reason')$$);
select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000001','c6600000-0000-0000-0000-000000000001','request','Changed plans');
select pg_temp.reject_write($$select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000001','c6600000-0000-0000-0000-000000000001','approve',null)$$);
select pg_temp.reject_write($$update public.orders set status='packing' where id='c6610000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_write($$update public.orders set status='shipped' where id='c6610000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_write($$update public.orders set tracking_provider='easyparcel',easyparcel_booking_state='booking' where id='c6610000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_write($$select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000001','c6600000-0000-0000-0000-000000000002','reject',null)$$);
select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000001','c6600000-0000-0000-0000-000000000002','reject','Already prepared; please contact us');
update public.orders set status='packing' where id='c6610000-0000-0000-0000-000000000001';
select pg_temp.reject_write($$select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000001','c6600000-0000-0000-0000-000000000001','request','Again')$$);
-- Booking already won: customer must contact support.
update public.orders set easyparcel_booking_state='booking',easyparcel_booking_started_at=now() where id='c6610000-0000-0000-0000-000000000002';
select pg_temp.reject_write($$select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000002','c6600000-0000-0000-0000-000000000001','request','Reason')$$);
-- Draft split plan is eligible; new claims and forged identities are held.
insert into public.order_parcels(order_id,parcel_number,items,weight_kg,length_cm,width_cm,height_cm,collection_date) select 'c6610000-0000-0000-0000-000000000003',n,'[{}]',1,10,10,10,'2099-01-01' from generate_series(1,2)n;
select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000003','c6600000-0000-0000-0000-000000000001','request','Reason');
select pg_temp.reject_write($$update public.order_parcels set state='booking' where order_id='c6610000-0000-0000-0000-000000000003'$$);
select pg_temp.reject_write($$update public.order_parcels set tracking_number='NEWAWB' where order_id='c6610000-0000-0000-0000-000000000003' and parcel_number=1$$);
select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000003','c6600000-0000-0000-0000-000000000002','approve','Approved');
select public.record_verified_refund('c6610000-0000-0000-0000-000000000003','pi_cancel_3','re_cancel',2000,'sgd','pending',now(),null);
select pg_temp.reject_write($$update public.orders set status='delivered' where id='c6610000-0000-0000-0000-000000000003'$$);
select public.record_verified_refund('c6610000-0000-0000-0000-000000000003','pi_cancel_3','re_cancel',2000,'sgd','failed',now(),'test_failure');
select pg_temp.reject_write($$update public.orders set status='shipped' where id='c6610000-0000-0000-0000-000000000003'$$);
select public.record_verified_refund('c6610000-0000-0000-0000-000000000003','pi_cancel_3','re_cancel',2000,'sgd','succeeded',now(),null);
do $$ begin if not exists(select 1 from public.orders where id='c6610000-0000-0000-0000-000000000003' and status='refunded')then raise exception 'Hold blocked verified refund';end if;end $$;
insert into public.order_parcels(order_id,parcel_number,items,weight_kg,length_cm,width_cm,height_cm,collection_date,state) values('c6610000-0000-0000-0000-000000000004',1,'[{}]',1,10,10,10,'2099-01-01','booking');
select pg_temp.reject_write($$select public.transition_order_cancellation('c6610000-0000-0000-0000-000000000004','c6600000-0000-0000-0000-000000000001','request','Reason')$$);
-- Client grants never permit spoofed decisions or hold deletion.
set local role authenticated;
select set_config('request.jwt.claim.sub','c6600000-0000-0000-0000-000000000002',true);
do $$ begin if has_table_privilege(current_user,'public.order_cancellation_requests','UPDATE') or has_table_privilege(current_user,'public.order_cancellation_requests','INSERT') or has_table_privilege(current_user,'public.order_cancellation_requests','DELETE') or has_function_privilege(current_user,'public.transition_order_cancellation(uuid,uuid,text,text)','execute') then raise exception 'Client can spoof cancellation state';end if;end $$;
reset role;
-- Account deletion must retain the financial decision without trapping auth.
insert into public.order_cancellation_requests(order_id,user_id,status,reason)
 values('c6610000-0000-0000-0000-000000000008','c6600000-0000-0000-0000-000000000003','requested','Deletion boundary fixture');
delete from auth.users where id='c6600000-0000-0000-0000-000000000003';
do $$ begin if not exists(select 1 from public.order_cancellation_requests where order_id='c6610000-0000-0000-0000-000000000008' and user_id is null) then raise exception 'Deleted account blocked or financial decision lost';end if;end $$;
select 'Cancellation lifecycle/fulfillment boundaries passed';
rollback;
