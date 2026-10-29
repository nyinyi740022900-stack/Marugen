-- Marugen Koi Farm — 0070: recover from a failed multi-parcel booking.
--
-- 1. The 0063 tracking guard treated the booking function's own failure
--    write (state needs_attention, no provider status code) as a stale
--    provider event and reverted `state`, so failed parcels stayed on
--    "Booking in progress" forever. A parcel with no provider identity has
--    no tracking evidence to protect, so the guard now skips it.
-- 2. `booking_error` keeps EasyParcel's short rejection reason for staff.
-- 3. reset_unsubmitted_parcel_plan returns a plan to draft only when no box
--    ever received a provider identity and nothing can still be running, so
--    staff can re-quote and book again after checking EasyParcel.
-- 4. discard_order_parcel_plan drops an unsubmitted split so the order can
--    ship as one parcel (one EasyParcel charge) instead.
begin;

alter table public.order_parcels
  add column if not exists booking_error text
  check (booking_error is null or length(booking_error) <= 300);

create or replace function public.guard_easyparcel_parcel_tracking() returns trigger language plpgsql set search_path=public as $$
begin
 if (old.tracking_number is not null or old.shipment_number is not null)
 and old.tracking_number is not distinct from new.tracking_number and old.shipment_number is not distinct from new.shipment_number
 and (new.tracking_status_code,new.tracking_status,new.tracking_updated_at,new.tracking_observed_at,new.tracking_event_at)
 is distinct from (old.tracking_status_code,old.tracking_status,old.tracking_updated_at,old.tracking_observed_at,old.tracking_event_at) then
  if not public.accept_easyparcel_tracking(old.tracking_status_code,old.tracking_progress,new.tracking_status_code,new.tracking_status,old.tracking_observed_at,coalesce(new.tracking_observed_at,clock_timestamp()),old.tracking_event_at,new.tracking_event_at) then
   new.state:=old.state;new.tracking_status_code:=old.tracking_status_code;new.tracking_status:=old.tracking_status;
   new.tracking_updated_at:=old.tracking_updated_at;new.tracking_observed_at:=old.tracking_observed_at;new.tracking_event_at:=old.tracking_event_at;new.tracking_progress:=old.tracking_progress;
  else new.tracking_progress:=greatest(old.tracking_progress,public.easyparcel_tracking_progress(new.tracking_status_code));end if;
 end if;
 return new;
end $$;

create or replace function public.reset_unsubmitted_parcel_plan(p_order_id uuid) returns setof public.order_parcels
language plpgsql security definer set search_path=public as $$
begin
 perform 1 from public.orders where id=p_order_id for update;
 if not found then raise exception 'Order not found';end if;
 if not exists(select 1 from public.order_parcels where order_id=p_order_id) then
  raise exception 'No parcel plan to reset';
 end if;
 -- Any provider identity means EasyParcel accepted a box: never rebook.
 if exists(select 1 from public.order_parcels where order_id=p_order_id and(
   state not in('booking','needs_attention')
   or tracking_number is not null or shipment_number is not null or awb_url is not null
   or diagnostic_code is null or diagnostic_code not in('submission_uncertain','not_attempted_after_failure')
   -- A booking request may still be in flight until well after its quote expired.
   or (state='booking' and (quote_expires_at is null or quote_expires_at>now()-interval '15 minutes'))))
 then raise exception 'Only a failed booking with no EasyParcel shipment can be reset';end if;
 return query
 update public.order_parcels set state='draft',diagnostic_code=null,booking_error=null,
   service_id=null,carrier_name=null,quoted_total_cents=null,quote_expires_at=null,quote_signature=null,
   tracking_status=null,tracking_updated_at=null
  where order_id=p_order_id returning *;
end $$;
revoke all on function public.reset_unsubmitted_parcel_plan(uuid) from public,anon,authenticated;
grant execute on function public.reset_unsubmitted_parcel_plan(uuid) to service_role;

-- Splitting is optional and every box is billed as its own shipment. Until
-- anything is submitted, staff can drop the split and ship one parcel
-- through the normal single-shipment booking again.
create or replace function public.discard_order_parcel_plan(p_order_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
 perform public.lock_order_parcel_plan(p_order_id);
 delete from public.order_parcels where order_id=p_order_id;
end $$;
revoke all on function public.discard_order_parcel_plan(uuid) from public,anon,authenticated;
grant execute on function public.discard_order_parcel_plan(uuid) to service_role;

-- Repair plans already stuck by the old guard (finished, never identified).
update public.order_parcels set state='needs_attention',tracking_status='Needs attention'
 where state='booking' and tracking_number is null and shipment_number is null
   and quote_expires_at<now()-interval '15 minutes';

commit;
