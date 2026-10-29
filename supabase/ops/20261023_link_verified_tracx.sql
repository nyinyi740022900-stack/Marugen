-- One-off, owner-authorized reconciliation of a legacy SAMPLE claim.
-- Evidence: connected SG Business10947427 All Parcels; downloaded label
-- QSP223261096.pdf references Marugen order19102026-0001, Johnny808735.
-- Live label resource ES-2610-5UF8T/7633145. Pickup scheduled2026-10-24.
-- No courier booking request, payment, financial snapshot or address edit.
begin;
do $$
declare before_row public.orders; after_row public.orders;
begin
 if not exists(select 1 from net._http_response r
   cross join lateral jsonb_array_elements(r.content::jsonb #> '{data,results}') t
   where r.id=7441 and r.status_code=200 and t->>'status'='success'
   and t->>'awb_number'='QSP223261096'
   and t->>'shipment_number'='ES-2610-5UF8T'
   and t->>'latest_shipment_status_code'='7')
 then raise exception 'Authenticated live tracking evidence missing'; end if;
 select * into strict before_row from public.orders
 where id='06806c1f-348e-439a-9d8e-eb0194edd2f7' for update;
 if before_row.order_number is distinct from '19102026-0001'
   or before_row.status is distinct from 'shipped'
   or before_row.fulfillment_method is distinct from 'courier'
   or before_row.tracking_provider is distinct from 'easyparcel'
   or before_row.tracking_registered is distinct from true
   or before_row.qxpress_tracking_no is distinct from 'EPSAMPLE17924122984637797262'
   or before_row.easyparcel_shipment_id is distinct from 'ES-2610-CXZDP'
   or before_row.easyparcel_booking_state is distinct from 'needs_attention'
 then raise exception 'Legacy claim changed; inspect before reconciling'; end if;
 if exists(select 1 from public.order_parcels where order_id=before_row.id)
   or exists(select 1 from public.orders where id<>before_row.id
     and(qxpress_tracking_no='QSP223261096' or easyparcel_shipment_id='ES-2610-5UF8T'))
   or exists(select 1 from public.order_parcels
     where tracking_number='QSP223261096' or shipment_number='ES-2610-5UF8T')
 then raise exception 'Parcel already linked or conflicting plan exists'; end if;
 update public.orders set
   qxpress_tracking_no='QSP223261096',
   easyparcel_shipment_id='ES-2610-5UF8T',
   easyparcel_awb_url='https://app.easyparcel.com/portal/v2/public/label/ES-2610-5UF8T/7633145?format=A4',
   easyparcel_booking_state='booked',
   tracking_status='Schedule In Arrangement',
   tracking_status_code=7,
   tracking_status_detail='TracX Logis pickup scheduled 24 Oct 2026. Receiver: Johnny, 14 Jalan Lekub, Singapore 808735.',
   tracking_updated_at=now()
 where id=before_row.id returning * into strict after_row;
 -- Assert EVERY other field is unchanged, including buyer charge and original
 -- payment-bound address, which is retained as purchase history.
 if (to_jsonb(before_row)-array['qxpress_tracking_no','easyparcel_shipment_id','easyparcel_awb_url','easyparcel_booking_state','tracking_status','tracking_status_code','tracking_status_detail','tracking_updated_at','updated_at'])
   is distinct from
   (to_jsonb(after_row)-array['qxpress_tracking_no','easyparcel_shipment_id','easyparcel_awb_url','easyparcel_booking_state','tracking_status','tracking_status_code','tracking_status_detail','tracking_updated_at','updated_at'])
 then raise exception 'Unexpected non-tracking mutation; rolled back'; end if;
end $$;
select order_number,qxpress_tracking_no,easyparcel_shipment_id,easyparcel_booking_state,
 tracking_status,tracking_status_code,easyparcel_awb_url
from public.orders where id='06806c1f-348e-439a-9d8e-eb0194edd2f7';
commit;
