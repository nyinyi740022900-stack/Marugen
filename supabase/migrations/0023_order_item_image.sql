-- Snapshot of the product's cover photo at order time — the product (and
-- its images) can change or be deleted later, but the order's item photo
-- should stay as it was at purchase.
alter table public.order_items
  add column if not exists image_url text;
