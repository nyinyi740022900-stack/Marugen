-- Numeric shipment status code (EasyParcel's own enum — see
-- https://easyparcel.github.io/OpenAPI/ "Shipment Status Codes": 0 Cancel,
-- 2 To Be Collected, 3 Collected, 4 Delivery In Transit, 5 Delivered,
-- 6 Returned, 7 Schedule In Arrangement, 8 On Hold, 11 Drop Off).
--
-- The existing tracking_status column is free text (courier-worded, e.g.
-- "Shipment data received - Awaiting Parcel Handover to DHL"), too varied
-- to reliably map to an icon in the UI. This numeric code lets the
-- customer-facing tracking card show a status-appropriate icon (e.g. a
-- "waiting for pickup" clock before the courier has collected the parcel,
-- vs. a truck once it's actually moving) without guessing from text.
-- Null for 17TRACK-tracked orders, which don't have this concept.
alter table public.orders
  add column if not exists tracking_status_code int;
