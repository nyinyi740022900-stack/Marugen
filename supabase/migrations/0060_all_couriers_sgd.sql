-- User requested all available couriers, with every displayed amount in SGD.
-- Preserve server ownership, immutable accepted quotes, exact splits and claims.
do $$
declare previous_name text;
begin
 select conname into previous_name from pg_constraint
 where conrelid='public.shipping_quotes'::regclass and contype='c'
 and pg_get_constraintdef(oid) like '%TracX Logis%';
 if previous_name is not null then
  execute format('alter table public.shipping_quotes drop constraint %I',previous_name);
 elsif not exists(select 1 from pg_constraint where conrelid='public.shipping_quotes'::regclass and conname='shipping_quote_delivery_policy') then
  raise exception 'Expected shipping quote carrier policy is missing';
 end if;
end $$;
alter table public.shipping_quotes drop constraint if exists shipping_quote_delivery_policy;
alter table public.shipping_quotes add constraint shipping_quote_delivery_policy check (
 (fulfillment_method='shop_delivery' and shipping_cost_policy='seller_100'
  and total_shipping_cents=0 and carrier_name is null and service_id is null and parcel is null)
 or (fulfillment_method='courier' and shipping_cost_policy='shared_50_50'
  and carrier_name is not null and length(btrim(carrier_name)) between 1 and 200
  and service_id is not null and length(btrim(service_id))>0 and parcel is not null
  and total_shipping_cents>0 and buyer_shipping_cents=total_shipping_cents/2
  and source_currency is not null and source_currency in('SGD','MYR')
  and source_shipping_amount is not null and source_shipping_amount>0
  and fx_rate is not null and fx_rate>0 and fx_date is not null and fx_source is not null)
);
create or replace function public.claim_courier_shipment(p_order_id uuid,p_provider text,p_tracking_number text default null,p_carrier_code integer default null)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if p_provider='seventeentrack' and p_carrier_code is not null and p_carrier_code<=0 then
  raise exception 'Carrier code must be a positive integer';
 end if;
 if p_provider='easyparcel' and not exists(
  select 1 from public.orders where id=p_order_id and shipping_quote_id is not null
  and nullif(btrim(shipping_carrier_name),'') is not null and shipping_currency='SGD'
  and nullif(btrim(shipping_service_id),'') is not null and shipping_parcel is not null
 ) then return false; end if;
 return public.claim_courier_shipment_before_finance(p_order_id,p_provider,p_tracking_number,p_carrier_code);
end; $$;
revoke all on function public.claim_courier_shipment(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.claim_courier_shipment(uuid,text,text,integer) to service_role;
