-- Product-level pellet/size labels for restockable goods (fish_food /
-- accessories). Independent of weight variants: size does not change
-- price or stock — it is a required pick when the list is non-empty.
alter table public.products
  add column if not exists size_options text[] not null default '{}';

-- Persist the customer's size choice on each order line for packing.
alter table public.order_items
  add column if not exists size_label text;
