begin;
-- One final decision per paid order. A request freezes fulfillment; approval
-- keeps that hold until the existing verified Stripe refund flow completes.
create table public.order_cancellation_requests (
 order_id uuid primary key references public.orders(id) on delete cascade,
 user_id uuid not null references public.profiles(id),
 status text not null default 'requested' check(status in('requested','approved','rejected')),
 reason text not null check(length(btrim(reason)) between 1 and 500),
 requested_at timestamptz not null default now(),
 review_note text check(length(review_note)<=500),
 reviewed_at timestamptz,
 reviewed_by uuid references public.profiles(id),
 check ((status='requested' and reviewed_at is null and reviewed_by is null)
  or (status in('approved','rejected') and reviewed_at is not null and reviewed_by is not null)),
 check (status<>'rejected' or length(btrim(review_note))>0)
);
alter table public.order_cancellation_requests enable row level security;
create policy order_cancellation_read on public.order_cancellation_requests for select to authenticated
 using(user_id=auth.uid() or public.is_admin());
revoke all on public.order_cancellation_requests from public,anon,authenticated;
grant select on public.order_cancellation_requests to authenticated;
grant all on public.order_cancellation_requests to service_role;

-- All entry points, including direct service writes and old deployed booking
-- functions, serialize on the order row. Tracking of an EXISTING identity is
-- still truthful; new claims, manual fulfillment and routing changes are held.
create function public.guard_order_cancellation_hold() returns trigger
language plpgsql security definer set search_path=public as $$
declare held boolean; existing_claim boolean;
begin
 select exists(select 1 from public.order_cancellation_requests where order_id=old.id and status in('requested','approved')) into held;
 if not held then return new;end if;
 existing_claim:=old.tracking_registered or old.tracking_provider is not null
  or nullif(btrim(old.qxpress_tracking_no),'') is not null or old.easyparcel_shipment_id is not null
  or old.easyparcel_booking_state is not null or old.easyparcel_booking_started_at is not null
  or exists(select 1 from public.order_parcels where order_id=old.id and state<>'draft');
 if new.fulfillment_method is distinct from old.fulfillment_method
 or (not existing_claim and (
  new.tracking_registered is distinct from old.tracking_registered
  or new.tracking_provider is distinct from old.tracking_provider
  or new.qxpress_tracking_no is distinct from old.qxpress_tracking_no
  or new.easyparcel_shipment_id is distinct from old.easyparcel_shipment_id
  or new.easyparcel_booking_state is distinct from old.easyparcel_booking_state
  or new.easyparcel_booking_started_at is distinct from old.easyparcel_booking_started_at))
 or (new.status is distinct from old.status and new.status in('packing','shipped','delivered')
  and not (existing_claim and new.status in('shipped','delivered'))) then
  raise exception 'Cancellation is awaiting resolution; fulfillment is on hold';
 end if;
 return new;
end $$;
create trigger orders_cancellation_hold before update on public.orders
 for each row execute function public.guard_order_cancellation_hold();

create function public.guard_parcel_cancellation_hold() returns trigger
language plpgsql security definer set search_path=public as $$
declare oid uuid;
begin
 if tg_op='DELETE' then oid:=old.order_id;else oid:=new.order_id;end if;
 -- Lock before consulting the hold, matching cancellation and parcel claims.
 perform 1 from public.orders where id=oid for update;
 if tg_op='UPDATE' and old.order_id is distinct from new.order_id then
  raise exception 'Parcel order identity is immutable';
 end if;
 if exists(select 1 from public.order_cancellation_requests where order_id=oid and status in('requested','approved')) then
  if tg_op='INSERT' or tg_op='DELETE' then
   raise exception 'Cancellation is awaiting resolution; parcel plan is on hold';
  end if;
  if old.state='draft' and (new.state is distinct from old.state
   or new.tracking_number is distinct from old.tracking_number
   or new.shipment_number is distinct from old.shipment_number
   or new.awb_url is distinct from old.awb_url) then
   raise exception 'Cancellation is awaiting resolution; parcel booking is on hold';
  end if;
 end if;
 if tg_op='DELETE' then return old;end if;
 return new;
end $$;
create trigger order_parcels_cancellation_hold before insert or update or delete on public.order_parcels
 for each row execute function public.guard_parcel_cancellation_hold();

-- Called with a verified JWT actor ONLY by the edge function's service client.
-- Neither clients nor staff JWTs can invoke it with a forged actor identity.
create function public.transition_order_cancellation(p_order_id uuid,p_actor_id uuid,p_action text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.orders;r public.order_cancellation_requests;admin_actor boolean;changed boolean:=false;
begin
 if p_action is null or p_action not in('request','approve','reject','refresh') then raise exception 'Invalid cancellation action';end if;
 select * into o from public.orders where id=p_order_id for update;
 if not found then raise exception 'Order not found' using errcode='P0002';end if;
 select exists(select 1 from public.profiles where id=p_actor_id and role in('owner','staff')) into admin_actor;
 if (p_action='request' and o.user_id is distinct from p_actor_id)
 or (p_action<>'request' and not admin_actor) then raise exception 'Cancellation access denied' using errcode='42501';end if;
 select * into r from public.order_cancellation_requests where order_id=p_order_id;
 if p_action='request' then
  if r.order_id is not null then
   if r.status='rejected' then raise exception 'Cancellation was declined; please contact support';end if;
   return jsonb_build_object('request',to_jsonb(r),'changed',false);
  end if;
  if o.status not in('paid','packing') or nullif(btrim(o.stripe_payment_intent_id),'') is null or o.refund_status is not null then raise exception 'Only paid, unshipped Stripe orders can request cancellation';end if;
  if o.tracking_progress<>0 or o.tracking_registered or o.tracking_provider is not null or nullif(btrim(o.qxpress_tracking_no),'') is not null
   or o.easyparcel_shipment_id is not null or o.easyparcel_booking_state is not null or o.easyparcel_booking_started_at is not null
   or exists(select 1 from public.order_parcels where order_id=p_order_id and(state<>'draft' or tracking_progress<>0 or tracking_number is not null or shipment_number is not null or awb_url is not null)) then
   raise exception 'Delivery booking has already started; please contact support';
  end if;
  if nullif(btrim(p_reason),'') is null or length(p_reason)>500 then raise exception 'A cancellation reason of 1 to 500 characters is required';end if;
  insert into public.order_cancellation_requests(order_id,user_id,reason) values(p_order_id,o.user_id,btrim(p_reason)) returning * into r;
  changed:=true;
 else
  if r.order_id is null then raise exception 'No cancellation request exists';end if;
  if p_action='refresh' then
   if r.status<>'approved' then raise exception 'Only an approved cancellation has a refund to refresh';end if;
  elsif p_action='approve' and r.status='approved' then
   null; -- Retry reconciles the existing Stripe refund, never reverses a decision.
  else
   if r.status<>'requested' then raise exception 'Cancellation request already decided';end if;
   if length(p_reason)>500 then raise exception 'Review note must be at most 500 characters';end if;
   if p_action='reject' and nullif(btrim(p_reason),'') is null then raise exception 'A reason is required when declining cancellation';end if;
   update public.order_cancellation_requests set status=case when p_action='approve' then 'approved' else 'rejected' end,
    review_note=nullif(btrim(p_reason),''),reviewed_at=clock_timestamp(),reviewed_by=p_actor_id where order_id=p_order_id returning * into r;
   changed:=true;
  end if;
 end if;
 return jsonb_build_object('request',to_jsonb(r),'changed',changed);
end $$;
revoke all on function public.transition_order_cancellation(uuid,uuid,text,text),public.guard_order_cancellation_hold(),public.guard_parcel_cancellation_hold() from public,anon,authenticated;
grant execute on function public.transition_order_cancellation(uuid,uuid,text,text) to service_role;
commit;
