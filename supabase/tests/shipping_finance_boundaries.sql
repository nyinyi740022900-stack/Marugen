\set ON_ERROR_STOP on
begin;
\ir ../migrations/0057_delivery_fulfillment.sql
insert into public.products(id,name,category,price) values('d5830000-0000-0000-0000-000000000001','Test food','fish_food',10);
insert into public.product_variants(product_id,label,price) values
 ('d5830000-0000-0000-0000-000000000001','500g',10),
 ('d5830000-0000-0000-0000-000000000001','1.5 kg',20),
 ('d5830000-0000-0000-0000-000000000001','Large 1kg box',20);
\ir ../migrations/0058_shipping_finance.sql
\ir ../migrations/0060_all_couriers_sgd.sql
do $$ begin
 if (select shipping_weight_kg from public.product_variants where label='500g') is distinct from 0.5::numeric
 or (select shipping_weight_kg from public.product_variants where label='1.5 kg') is distinct from 1.5::numeric
 or (select shipping_weight_kg from public.product_variants where label='Large 1kg box') is not null then
 raise exception 'Exact weight migration failed'; end if;
end $$;
insert into auth.users(id,email) values ('d5800000-0000-0000-0000-000000000001','shipping@example.invalid');
create function pg_temp.reject_write(statement text) returns void language plpgsql as $$ declare rejected boolean:=false; begin begin execute statement; exception when others then rejected:=true; end; if not rejected then raise exception 'Expected shipping write rejection: %',statement; end if; end $$;
insert into public.shipping_quotes(id,user_id,checkout_signature,pricing_signature,expires_at,currency,fulfillment_method,shipping_cost_policy,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,carrier_name,service_id,source_currency,source_shipping_amount,fx_rate,fx_date,fx_source,parcel) values ('d5810000-0000-0000-0000-000000000001','d5800000-0000-0000-0000-000000000001','C','P',now()+interval '15 minutes','SGD','courier','shared_50_50',405,202,203,'TracX Logis','S1','SGD',4.05,1,current_date,'EasyParcel native SGD','{}');
select pg_temp.reject_write($$update public.shipping_quotes set buyer_shipping_cents=0$$);
select pg_temp.reject_write($$insert into public.orders(user_id,total,fulfillment_method,shipping_quote_id) values('d5800000-0000-0000-0000-000000000001',12.02,'courier','d5810000-0000-0000-0000-000000000001')$$);
insert into public.orders(id,user_id,total,fulfillment_method,shipping_quote_id,shipping_checkout_signature,shipping_currency,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,shipping_cost_policy,shipping_carrier_name,shipping_service_id,shipping_source_currency,shipping_source_amount,shipping_fx_rate,shipping_fx_date,shipping_fx_source,shipping_parcel) values('d5820000-0000-0000-0000-000000000001','d5800000-0000-0000-0000-000000000001',12.02,'courier','d5810000-0000-0000-0000-000000000001','C','SGD',405,202,203,'shared_50_50','TracX Logis','S1','SGD',4.05,1,current_date,'EasyParcel native SGD','{}');
select pg_temp.reject_write($$update public.orders set buyer_shipping_cents=1 where id='d5820000-0000-0000-0000-000000000001'$$);
select pg_temp.reject_write($$insert into public.orders(user_id,total,fulfillment_method,shipping_quote_id,shipping_checkout_signature,shipping_currency,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,shipping_cost_policy,shipping_carrier_name,shipping_service_id,shipping_source_currency,shipping_source_amount,shipping_fx_rate,shipping_fx_date,shipping_fx_source,shipping_parcel) select user_id,total,fulfillment_method,shipping_quote_id,shipping_checkout_signature,shipping_currency,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,shipping_cost_policy,shipping_carrier_name,shipping_service_id,shipping_source_currency,shipping_source_amount,shipping_fx_rate,shipping_fx_date,shipping_fx_source,shipping_parcel from public.orders where id='d5820000-0000-0000-0000-000000000001'$$);
-- Every provider-returned named carrier can own an immutable SGD quote.
insert into public.shipping_quotes(id,user_id,checkout_signature,pricing_signature,expires_at,currency,fulfillment_method,shipping_cost_policy,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,carrier_name,service_id,source_currency,source_shipping_amount,fx_rate,fx_date,fx_source,parcel) values ('d5810000-0000-0000-0000-000000000002','d5800000-0000-0000-0000-000000000001','C2','P2',now()+interval '15 minutes','SGD','courier','shared_50_50',405,202,203,'J&T Express Singapore Pte Ltd','J1','SGD',4.05,1,current_date,'EasyParcel native SGD','{}');
insert into public.orders(id,user_id,status,total,fulfillment_method,shipping_quote_id,shipping_checkout_signature,shipping_currency,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,shipping_cost_policy,shipping_carrier_name,shipping_service_id,shipping_source_currency,shipping_source_amount,shipping_fx_rate,shipping_fx_date,shipping_fx_source,shipping_parcel) values('d5820000-0000-0000-0000-000000000002','d5800000-0000-0000-0000-000000000001','pending',12.02,'courier','d5810000-0000-0000-0000-000000000002','C2','SGD',405,202,203,'shared_50_50','J&T Express Singapore Pte Ltd','J1','SGD',4.05,1,current_date,'EasyParcel native SGD','{}');
update public.product_variants set stock_quantity=10 where label='500g';
insert into public.order_items(order_id,product_id,variant_id,product_name,product_category,quantity,unit_price) select 'd5820000-0000-0000-0000-000000000002',product_id,id,'Test food','fish_food',1,10 from public.product_variants where label='500g';
update public.orders set status='paid' where id='d5820000-0000-0000-0000-000000000002';
update public.orders set status='packing' where id='d5820000-0000-0000-0000-000000000002';
do $$ begin
 if not public.claim_courier_shipment('d5820000-0000-0000-0000-000000000002','easyparcel') then raise exception 'Non-TracX paid SGD shipment could not be claimed'; end if;
 if public.claim_courier_shipment('d5820000-0000-0000-0000-000000000002','easyparcel') then raise exception 'Duplicate shipment claimed'; end if;
end $$;
select pg_temp.reject_write($$update public.orders set shipping_carrier_name='Other' where id='d5820000-0000-0000-0000-000000000002'$$);
set local role authenticated;
select pg_temp.reject_write($$select * from public.shipping_quotes$$);
select pg_temp.reject_write($$insert into public.shipping_quotes(user_id) values('d5800000-0000-0000-0000-000000000001')$$);
reset role;
select 'shipping finance boundary checks passed';
rollback;
