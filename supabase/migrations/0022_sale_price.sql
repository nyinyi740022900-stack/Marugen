-- Per-product sale price (e.g. "$50 -> $35" badge on the card) — only
-- ever used when it's set AND strictly less than the regular price;
-- checked both client-side (display) and server-side (create-payment-intent).
alter table public.products
  add column if not exists sale_price numeric(10, 2);
