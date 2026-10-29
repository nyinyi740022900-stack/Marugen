-- Apply authenticated carrier evidence already read for the real shipment.
-- No booking, payment, address, item or financial changes.
begin;
do $$
declare before_row jsonb; after_row jsonb; applied jsonb; evidence jsonb;
begin
 select content::jsonb #> '{data,results,0}' into strict evidence
 from net._http_response where id=7785 and status_code=200;
 if evidence->>'status'<>'success' or evidence->>'awb_number'<>'QSP223261096'
 or evidence->>'shipment_number'<>'ES-2610-5UF8T'
 or not exists(select 1 from jsonb_array_elements(evidence->'status_log') e
   where e->>'shipment_status_code'='3' and e->>'tracking_status'='Pickup Done'
   and e->>'event_date'='2026-10-24 11:04:02') then
  raise exception 'Authenticated pickup evidence missing';
 end if;
 select to_jsonb(o) into strict before_row from public.orders o
 where id='06806c1f-348e-439a-9d8e-eb0194edd2f7'
 and order_number='19102026-0001' and qxpress_tracking_no='QSP223261096' for update;
 applied:=public.apply_easyparcel_order_tracking(
  '06806c1f-348e-439a-9d8e-eb0194edd2f7','QSP223261096','ES-2610-5UF8T',
  3,'Pickup Done','Singapore Hub',clock_timestamp(),'2026-10-24T03:04:02Z');
 select to_jsonb(o) into strict after_row from public.orders o
 where id='06806c1f-348e-439a-9d8e-eb0194edd2f7';
 if (after_row->>'tracking_progress')::int<1 then raise exception 'Pickup not retained';end if;
 if (before_row-array['tracking_status','tracking_status_code','tracking_status_detail',
   'tracking_updated_at','tracking_observed_at','tracking_event_at','tracking_progress','updated_at'])
 is distinct from
 (after_row-array['tracking_status','tracking_status_code','tracking_status_detail',
   'tracking_updated_at','tracking_observed_at','tracking_event_at','tracking_progress','updated_at'])
 then raise exception 'Unexpected non-tracking mutation';end if;
 -- Prove the incident's stale summary cannot undo verified custody, even
 -- when that stale response arrives in a later request.
 applied:=public.apply_easyparcel_order_tracking(
  '06806c1f-348e-439a-9d8e-eb0194edd2f7','QSP223261096','ES-2610-5UF8T',
  7,'Schedule In Arrangement',null,clock_timestamp(),'2026-10-23T07:15:26.442Z');
 if applied->>'applied'<>'false' or after_row is distinct from
   (select to_jsonb(o) from public.orders o where id='06806c1f-348e-439a-9d8e-eb0194edd2f7')
 then raise exception 'Stale summary regression';end if;
end $$;
select order_number,status,qxpress_tracking_no,tracking_status,tracking_status_code,
 tracking_progress,tracking_event_at from public.orders
where id='06806c1f-348e-439a-9d8e-eb0194edd2f7';
commit;
