-- Product variants (size/weight options) for restockable goods
-- (fish_food, accessories). Live fish (koi/arowana) never use this —
-- each fish is a single unique animal, not a set of variant options.
create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  label text not null, -- e.g. "500g", "1kg", "Small", "Large"
  price numeric(10,2) not null,
  stock_quantity int not null default 0,
  sku text,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.product_variants enable row level security;
create policy "Anyone can view variants" on public.product_variants for select using (true);
create policy "Admins can manage variants" on public.product_variants for all
  using (public.is_admin()) with check (public.is_admin());

-- Track which variant an order line item was for.
alter table public.order_items add column if not exists variant_id uuid references public.product_variants(id);
alter table public.order_items add column if not exists variant_label text;
