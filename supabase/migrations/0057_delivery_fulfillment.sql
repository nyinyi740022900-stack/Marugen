-- Durable purchase-time routing. Deleted products cannot turn live-fish
-- orders into courier parcels; unprovable legacy items require review.
alter table public.order_items add column product_category text
  check (product_category in ('koi','arowana','fish_food','accessories'));
alter table public.orders
  add column fulfillment_method text not null default 'review_required'
    check (fulfillment_method in ('shop_delivery','courier','review_required')),
  add column easyparcel_booking_state text
    check (easyparcel_booking_state in ('booking','booked','needs_attention')),
  add column easyparcel_booking_started_at timestamptz;

update public.order_items oi set product_category=p.category
from public.products p where p.id=oi.product_id;
update public.orders o set fulfillment_method=case
  when exists(select 1 from public.order_items i where i.order_id=o.id and i.product_category in ('koi','arowana')) then 'shop_delivery'
  when exists(select 1 from public.order_items i where i.order_id=o.id)
    and not exists(select 1 from public.order_items i where i.order_id=o.id and (i.product_category is null or i.product_category not in ('fish_food','accessories'))) then 'courier'
  else 'review_required' end;
update public.orders set easyparcel_booking_state=case
  when nullif(btrim(qxpress_tracking_no),'') is not null then 'booked'
  else 'needs_attention' end
where tracking_provider='easyparcel' and tracking_registered;

-- Historical manual registrations predate explicit provider ownership.
update public.orders set tracking_provider='seventeentrack'
where tracking_provider is null and tracking_registered
  and nullif(btrim(qxpress_tracking_no),'') is not null;

-- Invoker security is intentional: an authenticated staff JWT cannot use
-- direct UPDATE to erase a claim, relabel a live-fish order, or forge an AWB.
create function public.guard_server_owned_delivery() returns trigger
language plpgsql set search_path=public as $$
begin
  if current_user in ('postgres','supabase_admin','service_role') then return new; end if;
  if new.fulfillment_method is distinct from old.fulfillment_method
    or new.tracking_provider is distinct from old.tracking_provider
    or new.tracking_registered is distinct from old.tracking_registered
    or new.qxpress_tracking_no is distinct from old.qxpress_tracking_no
    or new.tracking_carrier_code is distinct from old.tracking_carrier_code
    or new.tracking_status is distinct from old.tracking_status
    or new.tracking_updated_at is distinct from old.tracking_updated_at
    or new.tracking_status_code is distinct from old.tracking_status_code
    or new.tracking_status_detail is distinct from old.tracking_status_detail
    or new.easyparcel_shipment_id is distinct from old.easyparcel_shipment_id
    or new.easyparcel_awb_url is distinct from old.easyparcel_awb_url
    or new.easyparcel_booking_state is distinct from old.easyparcel_booking_state
    or new.easyparcel_booking_started_at is distinct from old.easyparcel_booking_started_at then
      raise exception 'Delivery routing and courier records are managed by the delivery backend';
  end if;
  return new;
end; $$;
create trigger orders_server_owned_delivery before update on public.orders
for each row execute function public.guard_server_owned_delivery();

create function public.snapshot_order_item_category() returns trigger
language plpgsql set search_path=public as $$
begin
  if tg_op='UPDATE' then
    if new.product_category is distinct from old.product_category then
      raise exception 'Purchase-time product category is immutable';
    end if;
  else
    -- Ignore client-provided snapshots; use the trusted product row.
    select category into new.product_category from public.products where id=new.product_id;
  end if;
  return new;
end; $$;
create trigger order_items_category_snapshot before insert or update on public.order_items
for each row execute function public.snapshot_order_item_category();

-- New orders start pending, so recomputing after each line insert cannot
-- expose an incomplete basket to the paid/packing courier claim.
create function public.update_order_fulfillment_snapshot() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  update public.orders o set fulfillment_method=case
    when exists(select 1 from public.order_items i where i.order_id=o.id and i.product_category in ('koi','arowana')) then 'shop_delivery'
    when exists(select 1 from public.order_items i where i.order_id=o.id)
      and not exists(select 1 from public.order_items i where i.order_id=o.id and (i.product_category is null or i.product_category not in ('fish_food','accessories'))) then 'courier'
    else 'review_required' end
  where o.id=new.order_id;
  return new;
end; $$;
create trigger order_items_fulfillment_snapshot after insert on public.order_items
for each row execute function public.update_order_fulfillment_snapshot();

-- One database compare-and-set checks payment, immutable routing, every
-- snapshot and provider ownership while claiming. Restricted to service.
create function public.claim_courier_shipment(p_order_id uuid,p_provider text,p_tracking_number text default null,p_carrier_code integer default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare claimed uuid;
begin
  if p_provider not in ('easyparcel','seventeentrack') then raise exception 'Unsupported courier provider'; end if;
  update public.orders o set tracking_registered=true,tracking_provider=p_provider,
    qxpress_tracking_no=case when p_provider='seventeentrack' then p_tracking_number else o.qxpress_tracking_no end,
    tracking_carrier_code=case when p_provider='seventeentrack' then p_carrier_code else o.tracking_carrier_code end,
    tracking_status=case when p_provider='seventeentrack' then 'Registration pending' else o.tracking_status end,
    tracking_updated_at=case when p_provider='seventeentrack' then now() else o.tracking_updated_at end,
    status=case when p_provider='seventeentrack' then 'shipped' else o.status end,
    easyparcel_booking_state=case when p_provider='easyparcel' then 'booking' else null end,
    easyparcel_booking_started_at=case when p_provider='easyparcel' then now() else null end
  where o.id=p_order_id and (p_provider='easyparcel' or p_tracking_number ~ '^[A-Za-z0-9-]{3,100}$') and (o.status in ('paid','packing') or (p_provider='seventeentrack' and o.status='shipped'))
    and o.fulfillment_method='courier' and not o.tracking_registered
    and o.tracking_provider is null and nullif(btrim(o.qxpress_tracking_no),'') is null
    and exists(select 1 from public.order_items i where i.order_id=o.id)
    and not exists(select 1 from public.order_items i where i.order_id=o.id and (i.product_category is null or i.product_category not in ('fish_food','accessories')))
  returning o.id into claimed;
  return claimed is not null;
end; $$;
revoke all on function public.claim_courier_shipment(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.claim_courier_shipment(uuid,text,text,integer) to service_role;

-- Fail-closed legacy orders have one safe staff resolution: hand delivery.
-- This cannot select courier, touch a claim, or revive a terminal order.
create function public.confirm_shop_delivery(order_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare changed uuid;
begin
  if not public.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
  update public.orders o set fulfillment_method='shop_delivery'
  where o.id=order_id and o.status in ('paid','packing','shipped')
    and o.fulfillment_method='review_required' and not o.tracking_registered
    and o.tracking_provider is null and nullif(btrim(o.qxpress_tracking_no),'') is null
  returning o.id into changed;
  return changed is not null;
end; $$;
revoke all on function public.confirm_shop_delivery(uuid) from public,anon;
grant execute on function public.confirm_shop_delivery(uuid) to authenticated;
