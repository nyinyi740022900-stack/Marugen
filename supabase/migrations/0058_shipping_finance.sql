-- Shipping is quoted by the server, in integer SGD cents. No physical defaults
-- are invented: actual SKU kg is required; dimensions can be added at booking.
alter table public.settings
 add column default_parcel_length_cm numeric check(default_parcel_length_cm>0),
 add column default_parcel_width_cm numeric check(default_parcel_width_cm>0),
 add column default_parcel_height_cm numeric check(default_parcel_height_cm>0);
-- Exact weight labels can migrate safely. Ambiguous labels require admin entry.
alter table public.products add column shipping_weight_kg numeric check(shipping_weight_kg>0);
alter table public.product_variants add column shipping_weight_kg numeric check(shipping_weight_kg>0);
update public.product_variants v set shipping_weight_kg =
 (substring(lower(trim(v.label)) from '^([0-9]+(?:[.][0-9]+)?)')::numeric) /
 case when lower(trim(v.label)) ~ 'kg$' then 1 else 1000 end
 from public.products p where p.id=v.product_id and p.category in ('fish_food','accessories')
 and lower(trim(v.label)) ~ '^[0-9]+([.][0-9]+)?[ ]*(kg|g)$'
 and substring(lower(trim(v.label)) from '^([0-9]+(?:[.][0-9]+)?)')::numeric>0;
create table public.shipping_quotes(
 id uuid primary key default gen_random_uuid(),user_id uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),expires_at timestamptz not null,
 checkout_signature text not null,pricing_signature text not null,
 currency text not null check(currency='SGD'),
 fulfillment_method text not null check(fulfillment_method in('courier','shop_delivery')),
 shipping_cost_policy text not null check(shipping_cost_policy in('shared_50_50','seller_100')),
 total_shipping_cents integer not null check(total_shipping_cents>=0),
 buyer_shipping_cents integer not null check(buyer_shipping_cents>=0),
 seller_shipping_cents integer not null check(seller_shipping_cents>=0),
 carrier_name text,service_id text,parcel jsonb,source_currency text,source_shipping_amount numeric,
 fx_rate numeric,fx_date date,fx_source text,
 check(total_shipping_cents=buyer_shipping_cents+seller_shipping_cents),
 check((fulfillment_method='shop_delivery' and shipping_cost_policy='seller_100' and total_shipping_cents=0 and carrier_name is null and service_id is null and parcel is null)
 or (fulfillment_method='courier' and shipping_cost_policy='shared_50_50' and carrier_name='TracX Logis' and service_id is not null and parcel is not null and total_shipping_cents>0 and buyer_shipping_cents=total_shipping_cents/2 and source_currency in('SGD','MYR') and source_shipping_amount>0 and fx_rate>0 and fx_date is not null and fx_source is not null))
);
alter table public.shipping_quotes enable row level security;
revoke all on public.shipping_quotes from anon,authenticated;
grant select,insert on public.shipping_quotes to service_role;
create function public.immutable_shipping_quote() returns trigger language plpgsql as $$
begin
  -- Account deletion anonymizes the owner while retaining the financial record.
  if tg_op='UPDATE' and old.user_id is not null and new.user_id is null
    and (to_jsonb(new)-'user_id')=(to_jsonb(old)-'user_id') then return new; end if;
  raise exception 'Shipping quotes are immutable';
end; $$;
create trigger immutable_shipping_quotes before update or delete on public.shipping_quotes for each row execute function public.immutable_shipping_quote();
alter table public.orders
 add column shipping_quote_id uuid unique references public.shipping_quotes(id),
 add column shipping_currency text not null default 'SGD' check(shipping_currency='SGD'),
 add column total_shipping_cents integer not null default 0 check(total_shipping_cents>=0),
 add column buyer_shipping_cents integer not null default 0 check(buyer_shipping_cents>=0),
 add column seller_shipping_cents integer not null default 0 check(seller_shipping_cents>=0),
 add column shipping_carrier_name text,add column shipping_service_id text,add column shipping_parcel jsonb,
 add column shipping_source_currency text,add column shipping_source_amount numeric,
 add column shipping_fx_rate numeric,add column shipping_fx_date date,add column shipping_fx_source text,
 add column shipping_cost_policy text not null default 'seller_100' check(shipping_cost_policy in('shared_50_50','seller_100')),
 add column shipping_checkout_signature text,
 add constraint order_shipping_split check(total_shipping_cents=buyer_shipping_cents+seller_shipping_cents);
create function public.guard_shipping_finance() returns trigger language plpgsql set search_path=public as $$
declare q public.shipping_quotes; key text;
begin
 if tg_op='UPDATE' then
  foreach key in array array['shipping_quote_id','shipping_currency','total_shipping_cents','buyer_shipping_cents','seller_shipping_cents','shipping_carrier_name','shipping_service_id','shipping_parcel','shipping_source_currency','shipping_source_amount','shipping_fx_rate','shipping_fx_date','shipping_fx_source','shipping_cost_policy','shipping_checkout_signature'] loop
   if to_jsonb(new)->key is distinct from to_jsonb(old)->key then raise exception 'Paid shipping snapshots are immutable'; end if;
  end loop;
  if (old.shipping_quote_id is not null or old.stripe_payment_intent_id is not null) and new.shipping_address is distinct from old.shipping_address then raise exception 'Shipping address is bound to the accepted payment quote'; end if;
  return new;
 end if;
 if current_user not in('postgres','supabase_admin','service_role') then raise exception 'Shipping financial records are server owned'; end if;
 if new.shipping_quote_id is null then
  if new.fulfillment_method='courier' or new.total_shipping_cents<>0 then raise exception 'A current shipping quote is required for courier checkout'; end if;
  return new;
 end if;
 select * into q from public.shipping_quotes where id=new.shipping_quote_id;
 if not found or q.user_id is distinct from new.user_id or q.expires_at<=now() then raise exception 'Shipping quote expired or belongs to another buyer'; end if;
 if new.shipping_checkout_signature is distinct from q.checkout_signature or new.fulfillment_method is distinct from q.fulfillment_method or new.shipping_cost_policy is distinct from q.shipping_cost_policy
  or new.shipping_currency is distinct from q.currency or new.total_shipping_cents is distinct from q.total_shipping_cents or new.buyer_shipping_cents is distinct from q.buyer_shipping_cents or new.seller_shipping_cents is distinct from q.seller_shipping_cents
  or new.shipping_carrier_name is distinct from q.carrier_name or new.shipping_service_id is distinct from q.service_id or new.shipping_parcel is distinct from q.parcel or new.shipping_source_currency is distinct from q.source_currency or new.shipping_source_amount is distinct from q.source_shipping_amount or new.shipping_fx_rate is distinct from q.fx_rate or new.shipping_fx_date is distinct from q.fx_date or new.shipping_fx_source is distinct from q.fx_source then raise exception 'Order shipping does not match accepted quote'; end if;
 return new;
end; $$;
create trigger orders_shipping_finance before insert or update on public.orders for each row execute function public.guard_shipping_finance();
-- Keep the existing compare-and-set, adding a second boundary for the only
-- supported manual carrier and for prepaid EasyParcel service snapshots.
alter function public.claim_courier_shipment(uuid,text,text,integer) rename to claim_courier_shipment_before_finance;
revoke all on function public.claim_courier_shipment_before_finance(uuid,text,text,integer) from public,anon,authenticated,service_role;
create function public.claim_courier_shipment(p_order_id uuid,p_provider text,p_tracking_number text default null,p_carrier_code integer default null)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if p_provider='seventeentrack' and p_carrier_code is not null and p_carrier_code<>100190 then raise exception 'Only TracX Logis carrier 100190 is supported'; end if;
 if p_provider='easyparcel' and not exists(select 1 from public.orders where id=p_order_id and shipping_quote_id is not null and shipping_carrier_name='TracX Logis' and shipping_currency='SGD') then return false; end if;
 return public.claim_courier_shipment_before_finance(p_order_id,p_provider,p_tracking_number,case when p_provider='seventeentrack' then 100190 else null end);
end; $$;
revoke all on function public.claim_courier_shipment(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.claim_courier_shipment(uuid,text,text,integer) to service_role;
