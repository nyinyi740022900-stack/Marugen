-- Admin-configurable threshold for the "Low Stock" dashboard section and
-- the customer-facing "Only N left" nudge (both read the same value).
alter table public.settings
  add column if not exists low_stock_threshold int not null default 5;
