-- EasyParcel shipping API integration — auto shipment booking + auto
-- tracking, replacing manual tracking-number entry as the primary path
-- (manual entry / 17TRACK stays as a fallback, untouched).

-- Which system is tracking this order's shipment — lets the UI show the
-- right actions (e.g. hide "Enter Tracking Number" for an EasyParcel-
-- booked order) without touching the existing tracking_* columns' meaning
-- — EasyParcel tracking numbers are stored in the same qxpress_tracking_no/
-- tracking_status/tracking_status_detail/tracking_updated_at/
-- tracking_registered columns 17TRACK already uses, so the customer-facing
-- _TrackingStatusCard and OrderStatusTimeline need no changes at all.
alter table public.orders
  add column if not exists tracking_provider text
    check (tracking_provider in ('seventeentrack','easyparcel')),
  add column if not exists easyparcel_shipment_id text,
  add column if not exists easyparcel_awb_url text;

-- Structured sender address (EasyParcel's rate/booking APIs need postcode/
-- city/state separately, unlike the existing free-text shop_address) plus
-- the default parcel weight used for every rate quote — no per-product
-- weight tracking exists yet, so one admin-configurable default is used
-- for all orders (confirmed acceptable for this MVP).
alter table public.settings
  add column if not exists shop_postcode text,
  add column if not exists shop_city text,
  add column if not exists shop_state text,
  add column if not exists shop_country text not null default 'SG',
  add column if not exists default_parcel_weight_kg numeric not null default 1.0;

-- Singleton row holding the OAuth tokens for the connected EasyParcel
-- account. RLS enabled with NO select/insert/update policies for any
-- client role — only service-role Edge Functions (which bypass RLS) ever
-- read/write this; the admin app only ever sees a connected/not-connected
-- boolean via the easyparcel-status function, never the raw tokens.
create table if not exists public.easyparcel_connection (
  id int primary key default 1 check (id = 1),
  access_token text not null,
  refresh_token text not null,
  access_token_expires_at timestamptz not null,
  refresh_token_expires_at timestamptz not null,
  connected_at timestamptz not null default now(),
  connected_by uuid references public.profiles(id)
);
alter table public.easyparcel_connection enable row level security;
