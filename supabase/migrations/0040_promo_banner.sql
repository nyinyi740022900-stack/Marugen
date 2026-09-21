-- Promotional banner shown to customers once per device per day on app
-- open. Reuses the existing singleton `settings` table rather than a new
-- table — the app only ever needs one current promo image, same as
-- shop_phone/gst_percent/etc. No RLS change needed: settings is already
-- publicly readable / admin-writable, and the image itself reuses the
-- existing product-images bucket under a new banners/ prefix, already
-- covered by that bucket's is_admin() storage policies (0001_init.sql).
alter table public.settings
  add column if not exists promo_banner_image_url text,
  add column if not exists promo_banner_link_url text,
  add column if not exists promo_banner_active boolean not null default false;
