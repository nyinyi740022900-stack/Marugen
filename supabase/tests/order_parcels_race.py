"""Local PostgreSQL only. No network/provider calls."""
import concurrent.futures
import json
import subprocess
import sys

args = sys.argv[1:]
def sql(query, check=True):
    return subprocess.run(['psql', *args, '-Atqc', query], text=True, capture_output=True, check=check)

def fixture(n):
    quote = f'd5810000-0000-0000-0000-{n:012d}'
    order = f'd5820000-0000-0000-0000-{n:012d}'
    sql(f"""
insert into public.shipping_quotes(id,user_id,checkout_signature,pricing_signature,expires_at,currency,fulfillment_method,shipping_cost_policy,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,carrier_name,service_id,source_currency,source_shipping_amount,fx_rate,fx_date,fx_source,parcel)
select '{quote}',user_id,'R{n}','P',now()+interval '15 minutes',currency,fulfillment_method,shipping_cost_policy,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,carrier_name,service_id,source_currency,source_shipping_amount,fx_rate,fx_date,fx_source,parcel from public.shipping_quotes limit 1;
insert into public.orders(id,user_id,total,fulfillment_method,shipping_quote_id,shipping_checkout_signature,shipping_currency,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,shipping_cost_policy,shipping_carrier_name,shipping_service_id,shipping_source_currency,shipping_source_amount,shipping_fx_rate,shipping_fx_date,shipping_fx_source,shipping_parcel)
select '{order}',user_id,12.02,fulfillment_method,id,checkout_signature,currency,total_shipping_cents,buyer_shipping_cents,seller_shipping_cents,shipping_cost_policy,carrier_name,service_id,source_currency,source_shipping_amount,fx_rate,fx_date,fx_source,parcel from public.shipping_quotes where id='{quote}';
update public.product_variants set stock_quantity=100 where label='500g';
insert into public.order_items(order_id,product_id,variant_id,product_name,quantity,unit_price) select '{order}',product_id,id,'Food',2,5 from public.product_variants where label='500g';
update public.orders set status='paid' where id='{order}';
""")
    item = sql(f"select id from public.order_items where order_id='{order}'").stdout.strip()
    plan = json.dumps([dict(items=[dict(order_item_id=item, quantity=1)], weight_kg=1, length_cm=10, width_cm=10, height_cm=10, collection_date='2099-01-01')] * 2)
    return order, plan

# Both submissions race the same whole-plan claim. Only one may own spending.
order, plan = fixture(10)
sql(f"select public.save_order_parcel_plan('{order}','{plan}'::jsonb)")
sql(f"select public.quote_order_parcel_plan('{order}',(select jsonb_agg(jsonb_build_object('id',id,'service_id','S','carrier_name','Carrier','quoted_total_cents',500)) from public.order_parcels where order_id='{order}'),'race',now()+interval '10 minutes')")
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda _: sql(f"begin;select public.claim_order_parcel_plan('{order}','race',1000);select pg_sleep(0.2);commit",False), range(2)))
assert sum(r.returncode == 0 for r in results) == 1, [(r.returncode,r.stderr) for r in results]
assert sql(f"select count(*) from public.order_parcels where order_id='{order}' and state='booking'").stdout.strip() == '2'

# A legacy single claim and real split save cannot both win the order lock.
order, plan = fixture(11)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    single = pool.submit(sql, f"select public.claim_courier_shipment('{order}','easyparcel')", False)
    split = pool.submit(sql, f"select count(*) from public.save_order_parcel_plan('{order}','{plan}'::jsonb)", False)
    legacy, multi = single.result(), split.result()
legacy_won = legacy.returncode == 0 and legacy.stdout.strip() == 't'
split_won = multi.returncode == 0 and multi.stdout.strip() == '2'
assert legacy_won != split_won, (legacy.stdout, legacy.stderr, multi.stdout, multi.stderr)
print('Concurrent whole-plan claims and legacy/split lock races passed')

# Tracking/webhook requests race under the same order lock. A request started
# earlier may finish last; its higher-looking code must still be rejected.
order, _ = fixture(12)
assert sql(f"select public.claim_courier_shipment('{order}','easyparcel')").stdout.strip() == 't'
sql(f"update public.orders set qxpress_tracking_no='RACEAWB',easyparcel_shipment_id='RACESHIP' where id='{order}'")
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    newer = pool.submit(sql, f"begin;select public.apply_easyparcel_order_tracking('{order}','RACEAWB','RACESHIP',4,'In Transit',null,'2026-10-24 10:00Z');select pg_sleep(0.2);commit")
    older = pool.submit(sql, f"select public.apply_easyparcel_order_tracking('{order}','RACEAWB','RACESHIP',7,'Scheduled',null,'2026-10-24 09:00Z')")
    newer.result(); older.result()
assert sql(f"select status||':'||tracking_status_code||':'||tracking_status from public.orders where id='{order}'").stdout.strip() == 'shipped:4:In Transit'
# Deterministically take the newer snapshot lock first, then release a stale
# delivery response to finish later. Poll locks rather than assuming scheduling.
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    newer = pool.submit(sql, f"begin;set application_name='marugen_tracking_newer';select public.apply_easyparcel_order_tracking('{order}','RACEAWB','RACESHIP',4,'At Hub',null,'2026-10-24 11:00Z');select pg_sleep(0.5);commit")
    import time
    for _ in range(100):
        if sql("select count(*) from pg_stat_activity where application_name='marugen_tracking_newer' and wait_event='PgSleep'").stdout.strip() == '1':
            break
        time.sleep(0.005)
    else:
        raise AssertionError('Newer tracking transaction did not acquire row lock')
    older = pool.submit(sql, f"select public.apply_easyparcel_order_tracking('{order}','RACEAWB','RACESHIP',5,'Delivered',null,'2026-10-24 10:30Z')")
    newer.result(); older.result()
assert sql(f"select status||':'||tracking_status_code||':'||tracking_status from public.orders where id='{order}'").stdout.strip() == 'shipped:4:At Hub'
print('Concurrent tracking snapshots preserve transit and reject stale delivery')
# Split parcels use the same request-start timestamp and order-before-parcel
# lock order. Preserve all metadata when a delayed scheduling response arrives.
order, plan = fixture(13)
sql(f"select public.save_order_parcel_plan('{order}','{plan}'::jsonb)")
sql(f"update public.order_parcels set state='booked',tracking_number='PARCELRACE'||parcel_number,shipment_number='PARCELSHIP'||parcel_number where order_id='{order}'")
parcel = sql(f"select id from public.order_parcels where order_id='{order}' and parcel_number=1").stdout.strip()
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    fresh = pool.submit(sql, f"begin;select public.apply_order_parcel_tracking('{parcel}','PARCELRACE1','PARCELSHIP1',4,'In Transit','2026-10-24 10:00Z');select pg_sleep(0.2);commit")
    stale = pool.submit(sql, f"select public.apply_order_parcel_tracking('{parcel}','PARCELRACE1','PARCELSHIP1',7,'Scheduled','2026-10-24 09:00Z')")
    fresh.result(); stale.result()
assert sql(f"select state||':'||tracking_status_code||':'||tracking_status from public.order_parcels where id='{parcel}'").stdout.strip() == 'in_transit:4:In Transit'
assert sql(f"select status from public.orders where id='{order}'").stdout.strip() == 'shipped'
print('Concurrent split-parcel snapshots preserve parcel and aggregate lifecycle')
# A later return after transit remains distinct and retains custody evidence.
sql(f"select public.apply_order_parcel_tracking('{parcel}','PARCELRACE1','PARCELSHIP1',6,'Returned','2026-10-24 11:00Z')")
assert sql(f"select state||':'||tracking_status_code||':'||tracking_progress from public.order_parcels where id='{parcel}'").stdout.strip() == 'returned:6:2'
assert sql(f"select status from public.orders where id='{order}'").stdout.strip() == 'shipped'
sql(f"select public.apply_order_parcel_tracking('{parcel}','PARCELRACE1','PARCELSHIP1',4,'In Transit','2026-10-24 12:00Z')")
assert sql(f"select state||':'||tracking_status_code from public.order_parcels where id='{parcel}'").stdout.strip() == 'returned:6'
print('Fresh returns after custody are retained without falsely delivering')
# Returned without a previous custody scan does not itself prove collection.
order, plan = fixture(14)
sql(f"select public.save_order_parcel_plan('{order}','{plan}'::jsonb)")
sql(f"update public.order_parcels set state='booked',tracking_number='RETURNAWB'||parcel_number,shipment_number='RETURNSHIP'||parcel_number where order_id='{order}'")
parcel = sql(f"select id from public.order_parcels where order_id='{order}' and parcel_number=1").stdout.strip()
sql(f"select public.apply_order_parcel_tracking('{parcel}','RETURNAWB1','RETURNSHIP1',6,'Returned','2026-10-24 10:00Z')")
assert sql(f"select status from public.orders where id='{order}'").stdout.strip() == 'paid'
sql(f"select public.apply_order_parcel_tracking('{parcel}','RETURNAWB1','RETURNSHIP1',5,'Delivered','2026-10-24 11:00Z')")
assert sql(f"select state||':'||tracking_status_code from public.order_parcels where id='{parcel}'").stdout.strip() == 'returned:6'
print('Returned evidence stays distinct and never invents collection or delivery')
