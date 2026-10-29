begin;
-- Receipt time is not a provider event time. Keep request start separately so a
-- slow refresh cannot overwrite a later refresh/webhook that finished first.
alter table public.orders add column tracking_event_at timestamptz, add column tracking_observed_at timestamptz, add column tracking_progress smallint not null default 0;
alter table public.order_parcels add column tracking_event_at timestamptz, add column tracking_observed_at timestamptz, add column tracking_progress smallint not null default 0;
create function public.easyparcel_tracking_progress(code integer) returns smallint language sql immutable as $$
 select (case when code in(3,11) then 1 when code=4 then 2 when code=5 then 3 else 0 end)::smallint
$$;
-- Only stored carrier codes establish custody. In particular an old manually
-- shipped order does not establish collection, nor does a text substring.
update public.orders set tracking_progress=public.easyparcel_tracking_progress(tracking_status_code) where tracking_provider='easyparcel';
update public.order_parcels set tracking_progress=public.easyparcel_tracking_progress(tracking_status_code);
create function public.accept_easyparcel_tracking(old_code integer,progress smallint,new_code integer,new_text text,old_observed timestamptz,new_observed timestamptz,old_event timestamptz default null,new_event timestamptz default null) returns boolean language sql immutable as $$
 select coalesce(new_code in(0,2,3,4,5,6,7,8,11)
 and (old_observed is null or new_observed>=old_observed)
 and (old_event is null or new_event>=old_event)
 and (old_code not in(5,6) or new_code=old_code or old_code is null)
 and (progress=0 or (new_code in(0,8) or public.easyparcel_tracking_progress(new_code)>=progress))
 and (lower(btrim(coalesce(new_text,''))) not in('waiting payment','expired (unpaid)') or (progress=0 and new_code not in(3,4,5,6,11))),false)
$$;
-- Triggers protect direct writers too, including functions still running during
-- rollout. PostgreSQL rechecks OLD under the row lock after concurrent updates.
create function public.guard_easyparcel_order_tracking() returns trigger language plpgsql set search_path=public as $$
begin
 if current_user not in('postgres','supabase_admin','service_role') and (new.tracking_progress is distinct from old.tracking_progress or new.tracking_observed_at is distinct from old.tracking_observed_at or new.tracking_event_at is distinct from old.tracking_event_at)then raise exception 'Tracking evidence is managed by the delivery backend';end if;
 if old.tracking_provider='easyparcel' and new.tracking_provider='easyparcel'
 and old.qxpress_tracking_no is not distinct from new.qxpress_tracking_no
 and (new.tracking_status_code,new.tracking_status,new.tracking_status_detail,new.tracking_updated_at,new.tracking_observed_at,new.tracking_event_at)
 is distinct from (old.tracking_status_code,old.tracking_status,old.tracking_status_detail,old.tracking_updated_at,old.tracking_observed_at,old.tracking_event_at) then
  if not public.accept_easyparcel_tracking(old.tracking_status_code,old.tracking_progress,new.tracking_status_code,new.tracking_status,old.tracking_observed_at,coalesce(new.tracking_observed_at,clock_timestamp()),old.tracking_event_at,new.tracking_event_at) then
   new.tracking_status_code:=old.tracking_status_code;new.tracking_status:=old.tracking_status;new.tracking_status_detail:=old.tracking_status_detail;
   new.tracking_updated_at:=old.tracking_updated_at;new.tracking_observed_at:=old.tracking_observed_at;new.tracking_event_at:=old.tracking_event_at;new.tracking_progress:=old.tracking_progress;
   if new.status is distinct from old.status and new.status in('shipped','delivered')then new.status:=old.status;end if;
  else
   new.tracking_progress:=greatest(old.tracking_progress,public.easyparcel_tracking_progress(new.tracking_status_code));
  end if;
 end if;
 return new;
end $$;
create trigger orders_tracking_progress before update on public.orders for each row execute function public.guard_easyparcel_order_tracking();
create function public.guard_easyparcel_parcel_tracking() returns trigger language plpgsql set search_path=public as $$
begin
 if old.tracking_number is not distinct from new.tracking_number and old.shipment_number is not distinct from new.shipment_number
 and (new.tracking_status_code,new.tracking_status,new.tracking_updated_at,new.tracking_observed_at,new.tracking_event_at)
 is distinct from (old.tracking_status_code,old.tracking_status,old.tracking_updated_at,old.tracking_observed_at,old.tracking_event_at) then
  if not public.accept_easyparcel_tracking(old.tracking_status_code,old.tracking_progress,new.tracking_status_code,new.tracking_status,old.tracking_observed_at,coalesce(new.tracking_observed_at,clock_timestamp()),old.tracking_event_at,new.tracking_event_at) then
   new.state:=old.state;new.tracking_status_code:=old.tracking_status_code;new.tracking_status:=old.tracking_status;
   new.tracking_updated_at:=old.tracking_updated_at;new.tracking_observed_at:=old.tracking_observed_at;new.tracking_event_at:=old.tracking_event_at;new.tracking_progress:=old.tracking_progress;
  else new.tracking_progress:=greatest(old.tracking_progress,public.easyparcel_tracking_progress(new.tracking_status_code));end if;
 end if;
 return new;
end $$;
create trigger order_parcels_tracking_progress before update on public.order_parcels for each row execute function public.guard_easyparcel_parcel_tracking();
-- Atomic identity check, evidence merge and lifecycle advance. Returns the
-- committed display values; a rejected stale response must not leak into UI.
create function public.apply_easyparcel_order_tracking(p_order_id uuid,p_awb text,p_shipment text,p_code integer,p_text text,p_detail text,p_observed_at timestamptz,p_event_at timestamptz default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.orders; next_status text; accepted boolean;
begin
 select * into strict o from public.orders where id=p_order_id for update;
 if o.tracking_provider is distinct from 'easyparcel' or o.qxpress_tracking_no is distinct from p_awb
 or (o.easyparcel_shipment_id is not null and o.easyparcel_shipment_id is distinct from p_shipment)
 or exists(select 1 from public.order_parcels where order_id=p_order_id) then raise exception 'Verified tracking identity does not match order';end if;
 accepted:=o.status in('paid','packing','shipped','delivered') and p_observed_at is not null and public.accept_easyparcel_tracking(o.tracking_status_code,o.tracking_progress,p_code,p_text,o.tracking_observed_at,p_observed_at,o.tracking_event_at,p_event_at);
 next_status:=o.status;
 if accepted then
  if p_code=5 and o.status in('paid','packing','shipped')then next_status:='delivered';
  elsif p_code in(3,4,11) and o.status in('paid','packing')then next_status:='shipped';end if;
  update public.orders set status=next_status,tracking_status=left(p_text,300),tracking_status_code=p_code,tracking_status_detail=left(p_detail,1000),tracking_updated_at=clock_timestamp(),tracking_observed_at=p_observed_at,tracking_event_at=p_event_at,easyparcel_booking_state='booked' where id=p_order_id;
 end if;
 return (select jsonb_build_object('applied',accepted,'status_changed',next_status is distinct from o.status,'order_status',status,'status',tracking_status,'detail',tracking_status_detail,'code',tracking_status_code) from public.orders where id=p_order_id);
end $$;
drop function public.apply_order_parcel_tracking(uuid,text,text,integer,text);
create function public.apply_order_parcel_tracking(p_parcel_id uuid,p_awb text,p_shipment text,p_code integer,p_text text,p_observed_at timestamptz default clock_timestamp(),p_event_at timestamptz default null) returns void language plpgsql security definer set search_path=public as $$
declare oid uuid; current_status text; next_state text; p public.order_parcels;
begin
 select order_id into oid from public.order_parcels where id=p_parcel_id;
 select status into current_status from public.orders where id=oid for update;
 if current_status in('refunded','cancelled')then return;end if;
 select * into strict p from public.order_parcels where id=p_parcel_id for update;
 if p.tracking_number is distinct from p_awb or p.shipment_number is distinct from p_shipment or p.state in('draft','booking') then raise exception 'Verified tracking identity does not match parcel';end if;
 if not public.accept_easyparcel_tracking(p.tracking_status_code,p.tracking_progress,p_code,p_text,p.tracking_observed_at,p_observed_at,p.tracking_event_at,p_event_at)then return;end if;
 next_state:=case when lower(btrim(coalesce(p_text,''))) in('waiting payment','expired (unpaid)')then 'payment_required' else case p_code when 0 then 'cancelled' when 3 then 'collected' when 4 then 'in_transit' when 5 then 'delivered' when 6 then 'returned' when 8 then 'on_hold' when 11 then 'collected' else 'booked' end end;
 update public.order_parcels set state=next_state,tracking_status=left(p_text,300),tracking_status_code=p_code,tracking_updated_at=clock_timestamp(),tracking_observed_at=p_observed_at,tracking_event_at=p_event_at where id=p_parcel_id;
 if not exists(select 1 from public.order_parcels where order_id=oid and state<>'delivered')then
  update public.orders set status='delivered' where id=oid and status in('paid','packing','shipped');
 elsif exists(select 1 from public.order_parcels where order_id=oid and tracking_progress>0)then
  update public.orders set status='shipped' where id=oid and status in('paid','packing');
 end if;
end $$;
revoke all on function public.apply_easyparcel_order_tracking(uuid,text,text,integer,text,text,timestamptz,timestamptz),public.apply_order_parcel_tracking(uuid,text,text,integer,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.apply_easyparcel_order_tracking(uuid,text,text,integer,text,text,timestamptz,timestamptz),public.apply_order_parcel_tracking(uuid,text,text,integer,text,timestamptz,timestamptz) to service_role;
commit;
