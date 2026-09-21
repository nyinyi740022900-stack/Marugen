-- Services catalog (e.g. "Fish Recovery & Quarantine", "Pond Renovation
-- Boarding") — admin-managed, shown alongside Varieties/Guides.
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  image_urls text[] not null default '{}',
  price numeric(10, 2),
  show_price boolean not null default true,
  category text,
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.services enable row level security;

create policy "Anyone can view active services"
  on public.services for select using (active = true);

create policy "Admins can view all services"
  on public.services for select using (public.is_admin());

create policy "Admins can manage services"
  on public.services for all
  using (public.is_admin()) with check (public.is_admin());

-- Growth-stage gallery per variety (e.g. Tosai/Nisai/Sansai with photos),
-- shown on the variety detail sheet.
alter table public.varieties
  add column if not exists stages jsonb not null default '[]'::jsonb;

-- Product-view events — one row per product-detail open. Insert-only from
-- the client (anon or authenticated); only admin can read/aggregate.
create table if not exists public.product_views (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products (id) on delete set null,
  user_id uuid references auth.users (id) on delete set null,
  viewed_at timestamptz not null default now()
);

alter table public.product_views enable row level security;

create policy "Anyone can log a product view"
  on public.product_views for insert with check (true);

create policy "Admins can read product views"
  on public.product_views for select using (public.is_admin());

-- App-visit events — one row per app open (customer side). Same
-- insert-open/read-admin-only shape as product_views.
create table if not exists public.app_visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  visited_at timestamptz not null default now()
);

alter table public.app_visits enable row level security;

create policy "Anyone can log an app visit"
  on public.app_visits for insert with check (true);

create policy "Admins can read app visits"
  on public.app_visits for select using (public.is_admin());

create index if not exists product_views_viewed_at_idx on public.product_views (viewed_at desc);
create index if not exists app_visits_visited_at_idx on public.app_visits (visited_at desc);
