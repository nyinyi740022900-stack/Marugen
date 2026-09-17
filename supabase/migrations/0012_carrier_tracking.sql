-- Marugen Koi Farm — 0012: carrier tracking (17TRACK integration)
-- Run with: supabase db push   (or paste into the Supabase SQL editor)
--
-- Lets admin register ANY courier's tracking number (Qxpress or otherwise)
-- with 17TRACK, which then pushes live status updates back via webhook —
-- so customers see real "In transit / Out for delivery / Delivered"
-- status instead of just a static tracking number.

alter table public.orders
  add column if not exists tracking_carrier_code int,
  add column if not exists tracking_status text,
  add column if not exists tracking_status_detail text,
  add column if not exists tracking_updated_at timestamptz,
  add column if not exists tracking_registered boolean not null default false;

comment on column public.orders.tracking_carrier_code is
  '17TRACK numeric carrier code (auto-detected on register if left null).';
comment on column public.orders.tracking_status is
  'Coarse status from 17TRACK, e.g. InTransit / OutForDelivery / Delivered / Exception.';
comment on column public.orders.tracking_status_detail is
  'Latest human-readable tracking event text from the carrier.';
