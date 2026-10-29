-- Actual packing plan and independent courier claims. Accepted checkout money
-- remains on orders; these seller-paid operational quotes never reprice it.
begin;
create table public.order_parcels (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete cascade,
 parcel_number integer not null check(parcel_number between 1 and 20),
 items jsonb not null check(jsonb_typeof(items)='array' and jsonb_array_length(items)>0),
 weight_kg numeric not null check(weight_kg>0),length_cm numeric not null check(length_cm>0),width_cm numeric not null check(width_cm>0),height_cm numeric not null check(height_cm>0),
 collection_date date not null,
 state text not null default 'draft' check(state in('draft','booking','booked','needs_attention','collected','in_transit','delivered','cancelled','returned','on_hold','payment_required')),
 service_id text,carrier_name text,quoted_total_cents integer check(quoted_total_cents>0),quote_expires_at timestamptz,quote_signature text,
 tracking_number text,shipment_number text,awb_url text,tracking_status text,tracking_status_code integer,tracking_updated_at timestamptz,
 diagnostic_code text check(diagnostic_code in('submission_uncertain','not_attempted_after_failure','sample_tracking','payment_required','missing_tracking')),
 created_at timestamptz not null default now(),unique(order_id,parcel_number)
);
create unique index order_parcels_awb_unique on public.order_parcels(tracking_number) where tracking_number is not null;
create unique index order_parcels_shipment_unique on public.order_parcels(shipment_number) where shipment_number is not null;
alter table public.order_parcels enable row level security;
create policy order_parcels_read on public.order_parcels for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and(o.user_id=auth.uid() or public.is_admin())));
revoke all on public.order_parcels from public,anon,authenticated;
grant select on public.order_parcels to authenticated;
grant all on public.order_parcels to service_role;

-- All competing operations take the SAME order row lock as single-shipment
-- UPDATE claims. No reset is available once any parcel has been submitted.
create function public.lock_order_parcel_plan(p_order_id uuid,p_draft boolean default true) returns void language plpgsql security definer set search_path=public as $$
declare o public.orders;
begin
 select * into o from public.orders where id=p_order_id for update;
 if not found then raise exception 'Order not found';end if;
 if o.status not in('paid','packing') or o.fulfillment_method<>'courier' or o.shipping_quote_id is null or o.shipping_currency<>'SGD'
 or o.tracking_registered or o.tracking_provider is not null or nullif(btrim(o.qxpress_tracking_no),'') is not null or o.easyparcel_shipment_id is not null or o.easyparcel_booking_state is not null or o.easyparcel_booking_started_at is not null
 or not exists(select 1 from public.order_items where order_id=p_order_id)
 or exists(select 1 from public.order_items where order_id=p_order_id and(product_category is null or product_category not in('fish_food','accessories')))
 then raise exception 'Order is not eligible for a new parcel plan';end if;
 if p_draft and exists(select 1 from public.order_parcels where order_id=p_order_id and state<>'draft') then raise exception 'Submitted parcel plan cannot be reset or retried';end if;
end $$;
create function public.save_order_parcel_plan(p_order_id uuid,p_parcels jsonb) returns setof public.order_parcels language plpgsql security definer set search_path=public as $$
declare b jsonb;i jsonb;n integer:=0;d date;
begin
 perform public.lock_order_parcel_plan(p_order_id);
 if jsonb_typeof(p_parcels)<>'array' or jsonb_array_length(p_parcels) not between 2 and 20 then raise exception 'Plan needs 2 to 20 actual boxes';end if;
 for b in select value from jsonb_array_elements(p_parcels) loop
  if jsonb_typeof(b->'items')<>'array' or jsonb_array_length(b->'items')=0 then raise exception 'Each parcel needs items';end if;
  if exists(select 1 from jsonb_array_elements(b->'items') x group by x->>'order_item_id' having count(*)>1) then raise exception 'Duplicate line in box';end if;
  for i in select value from jsonb_array_elements(b->'items') loop
   if jsonb_typeof(i->'quantity') is distinct from 'number' or (i->>'quantity')::numeric<>trunc((i->>'quantity')::numeric) or (i->>'quantity')::numeric<1
    or not exists(select 1 from public.order_items where id=(i->>'order_item_id')::uuid and order_id=p_order_id) then raise exception 'Invalid item allocation';end if;
  end loop;
  d:=(b->>'collection_date')::date;
  if d is null or d<=(now() at time zone 'Asia/Singapore')::date then raise exception 'Collection date must be in the future in Singapore';end if;
  if exists(select 1 from unnest(array['weight_kg','length_cm','width_cm','height_cm']) k where jsonb_typeof(b->k) is distinct from 'number' or (b->>k)::numeric<=0) then raise exception 'Positive actual box measurements required';end if;
 end loop;
 if exists(select 1 from public.order_items oi left join(
  select (allocated.item->>'order_item_id')::uuid id,sum((allocated.item->>'quantity')::numeric) qty from jsonb_array_elements(p_parcels) boxes(box) cross join lateral jsonb_array_elements(boxes.box->'items') allocated(item) group by 1
 ) a on a.id=oi.id where oi.order_id=p_order_id and coalesce(a.qty,0)<>oi.quantity) then raise exception 'Allocate every ordered unit exactly once';end if;
 delete from public.order_parcels where order_id=p_order_id;
 for b in select value from jsonb_array_elements(p_parcels) loop
  n:=n+1;
  insert into public.order_parcels(order_id,parcel_number,items,weight_kg,length_cm,width_cm,height_cm,collection_date)values(p_order_id,n,b->'items',(b->>'weight_kg')::numeric,(b->>'length_cm')::numeric,(b->>'width_cm')::numeric,(b->>'height_cm')::numeric,(b->>'collection_date')::date);
 end loop;
 return query select * from public.order_parcels where order_id=p_order_id order by parcel_number;
end $$;
create function public.quote_order_parcel_plan(p_order_id uuid,p_quotes jsonb,p_signature text,p_expires_at timestamptz) returns void language plpgsql security definer set search_path=public as $$
declare q jsonb; parcel_count integer;
begin
 perform public.lock_order_parcel_plan(p_order_id);
 select count(*) into parcel_count from public.order_parcels where order_id=p_order_id;
 if parcel_count<2 or jsonb_array_length(p_quotes)<>parcel_count or p_signature is null or p_expires_at<=now() or p_expires_at>now()+interval '20 minutes' then raise exception 'Invalid quote';end if;
 if (select count(distinct x->>'id') from jsonb_array_elements(p_quotes) x)<>parcel_count then raise exception 'Duplicate quote parcel';end if;
 for q in select value from jsonb_array_elements(p_quotes) loop
  update public.order_parcels set service_id=q->>'service_id',carrier_name=q->>'carrier_name',quoted_total_cents=(q->>'quoted_total_cents')::integer,quote_signature=p_signature,quote_expires_at=p_expires_at
   where id=(q->>'id')::uuid and order_id=p_order_id and state='draft';
  if not found or nullif(q->>'service_id','') is null or nullif(q->>'carrier_name','') is null or (q->>'quoted_total_cents') is null then raise exception 'Quote does not match current plan';end if;
 end loop;
end $$;
create function public.claim_order_parcel_plan(p_order_id uuid,p_signature text,p_approved_total_cents integer) returns boolean language plpgsql security definer set search_path=public as $$
begin
 perform public.lock_order_parcel_plan(p_order_id);
 if (select count(*) from public.order_parcels where order_id=p_order_id)<2
 or exists(select 1 from public.order_parcels where order_id=p_order_id and(quote_signature is distinct from p_signature or quote_expires_at is null or quote_expires_at<=now() or service_id is null or quoted_total_cents is null or collection_date<=(now() at time zone 'Asia/Singapore')::date))
 or p_approved_total_cents is null or p_approved_total_cents<>(select sum(quoted_total_cents) from public.order_parcels where order_id=p_order_id) then raise exception 'Fresh quote and exact owner approval required';end if;
 update public.order_parcels set state='booking',diagnostic_code='submission_uncertain' where order_id=p_order_id;
 return true;
end $$;

-- Wrap the existing immutable-finance claim instead of replacing its guards.
alter function public.claim_courier_shipment(uuid,text,text,integer) rename to claim_courier_shipment_before_parcels;
revoke all on function public.claim_courier_shipment_before_parcels(uuid,text,text,integer) from public,anon,authenticated,service_role;
create function public.claim_courier_shipment(p_order_id uuid,p_provider text,p_tracking_number text default null,p_carrier_code integer default null) returns boolean language plpgsql security definer set search_path=public as $$
begin
 perform 1 from public.orders where id=p_order_id for update;
 if exists(select 1 from public.order_parcels where order_id=p_order_id)then return false;end if;
 return public.claim_courier_shipment_before_parcels(p_order_id,p_provider,p_tracking_number,p_carrier_code);
end $$;

create function public.apply_order_parcel_tracking(p_parcel_id uuid,p_awb text,p_shipment text,p_code integer,p_text text) returns void language plpgsql security definer set search_path=public as $$
declare oid uuid; current_status text; next_state text;
begin
 select order_id into oid from public.order_parcels where id=p_parcel_id;
 select status into current_status from public.orders where id=oid for update;
 if current_status in('refunded','cancelled')then return;end if;
 next_state:=case when lower(btrim(coalesce(p_text,''))) in('waiting payment','expired (unpaid)')then 'payment_required' else case p_code when 0 then 'cancelled' when 3 then 'collected' when 4 then 'in_transit' when 5 then 'delivered' when 6 then 'returned' when 8 then 'on_hold' when 11 then 'collected' else 'booked' end end;
 update public.order_parcels set state=case when state='delivered' then 'delivered' else next_state end,tracking_status=case when state='delivered' and next_state<>'delivered' then tracking_status else left(p_text,300) end,tracking_status_code=p_code,tracking_updated_at=now()
  where id=p_parcel_id and tracking_number=p_awb and shipment_number=p_shipment and state not in('draft','booking');
 if not found then raise exception 'Verified tracking identity does not match parcel';end if;
 if not exists(select 1 from public.order_parcels where order_id=oid and state<>'delivered')then
  update public.orders set status='delivered' where id=oid and status in('paid','packing','shipped');
 elsif exists(select 1 from public.order_parcels where order_id=oid and state in('collected','in_transit','delivered'))then
  update public.orders set status='shipped' where id=oid and status in('paid','packing');
 end if;
end $$;
-- Attach recovered provider identities only to an existing submitted claim.
-- Caller must verify shipment/details AND tracking_status before invoking.
create function public.recover_order_parcel_identity(p_parcel_id uuid,p_shipment text,p_awb text,p_awb_url text) returns void language plpgsql security definer set search_path=public as $$
declare oid uuid; current_status text;
begin
 select order_id into oid from public.order_parcels where id=p_parcel_id;
 select status into current_status from public.orders where id=oid for update;
 if current_status in('refunded','cancelled')then return;end if;
 if nullif(btrim(p_awb),'') is null or p_awb ilike 'EPSAMPLE%' or p_shipment ilike 'EPSAMPLE%' then raise exception 'Real provider identity required';end if;
 update public.order_parcels set tracking_number=p_awb,awb_url=case when p_awb_url like 'https://%' then p_awb_url else awb_url end
 where id=p_parcel_id and shipment_number=p_shipment and (tracking_number is null or tracking_number=p_awb) and state not in('draft','booking');
 if not found then raise exception 'Existing parcel identity changed';end if;
end $$;
revoke all on function public.recover_order_parcel_identity(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.recover_order_parcel_identity(uuid,text,text,text) to service_role;
-- Protect legacy admin status controls too: one delivered box is insufficient.
create function public.guard_order_parcel_completion() returns trigger language plpgsql set search_path=public as $$
begin
 if new.status='delivered' and old.status is distinct from new.status and exists(select 1 from public.order_parcels where order_id=new.id and state<>'delivered') then raise exception 'Every parcel must be delivered before completing this order';end if;
 return new;
end $$;
create trigger orders_parcel_completion before update of status on public.orders for each row execute function public.guard_order_parcel_completion();
revoke all on function public.lock_order_parcel_plan(uuid,boolean),public.save_order_parcel_plan(uuid,jsonb),public.quote_order_parcel_plan(uuid,jsonb,text,timestamptz),public.claim_order_parcel_plan(uuid,text,integer),public.apply_order_parcel_tracking(uuid,text,text,integer,text),public.claim_courier_shipment(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.save_order_parcel_plan(uuid,jsonb),public.quote_order_parcel_plan(uuid,jsonb,text,timestamptz),public.claim_order_parcel_plan(uuid,text,integer),public.apply_order_parcel_tracking(uuid,text,text,integer,text),public.claim_courier_shipment(uuid,text,text,integer) to service_role;
commit;
