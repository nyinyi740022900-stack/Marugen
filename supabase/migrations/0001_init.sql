-- Marugen Koi Farm — initial schema + Row Level Security policies.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- profiles: one row per auth.users row, carries the app-level role.
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  phone text,
  full_name text,
  role text not null default 'customer' check (role in ('customer', 'staff', 'owner')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Auto-create a profile row whenever someone signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Helper used by RLS policies below to check "is this caller staff/owner?".
create or replace function public.is_admin()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('staff', 'owner')
  );
$$;

-- ---------------------------------------------------------------------
-- products
-- ---------------------------------------------------------------------
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  category text not null check (category in ('koi', 'arowana', 'fish_food', 'accessories')),
  price numeric(10, 2),
  show_price boolean not null default true,
  stock_quantity int not null default 0,
  image_urls text[] not null default '{}',
  video_url text,
  fish_details jsonb, -- {variety, size_cm, gender, breeder, has_certificate}
  is_sold boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.products enable row level security;

create policy "Anyone can view products"
  on public.products for select
  using (true);

create policy "Admins can manage products"
  on public.products for all
  using (public.is_admin())
  with check (public.is_admin());

-- ---------------------------------------------------------------------
-- varieties (koi/arowana knowledge catalog) & knowledge_articles (guides)
-- ---------------------------------------------------------------------
create table if not exists public.varieties (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null check (category in ('koi', 'arowana')),
  description text,
  image_url text,
  traits text[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.varieties enable row level security;

create policy "Anyone can view varieties"
  on public.varieties for select using (true);

create policy "Admins can manage varieties"
  on public.varieties for all
  using (public.is_admin()) with check (public.is_admin());

create table if not exists public.knowledge_articles (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body_markdown text not null,
  cover_image_url text,
  published_at timestamptz default now(),
  created_at timestamptz not null default now()
);

alter table public.knowledge_articles enable row level security;

create policy "Anyone can view articles"
  on public.knowledge_articles for select using (true);

create policy "Admins can manage articles"
  on public.knowledge_articles for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- orders & order_items
-- ---------------------------------------------------------------------
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'packing', 'shipped', 'delivered', 'cancelled', 'refunded')),
  total numeric(10, 2) not null default 0,
  stripe_payment_intent_id text,
  qxpress_tracking_no text,
  shipping_address jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.orders enable row level security;

create policy "Users can view their own orders"
  on public.orders for select using (auth.uid() = user_id);

create policy "Users can create their own orders"
  on public.orders for insert with check (auth.uid() = user_id);

create policy "Admins can view all orders"
  on public.orders for select using (public.is_admin());

create policy "Admins can update orders"
  on public.orders for update using (public.is_admin());

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid references public.products (id),
  product_name text not null,
  quantity int not null default 1,
  unit_price numeric(10, 2) not null default 0
);

alter table public.order_items enable row level security;

create policy "Users can view items of their own orders"
  on public.order_items for select
  using (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

create policy "Users can insert items into their own orders"
  on public.order_items for insert
  with check (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

create policy "Admins can view all order items"
  on public.order_items for select using (public.is_admin());

-- ---------------------------------------------------------------------
-- settings (single row, id = 1)
-- ---------------------------------------------------------------------
create table if not exists public.settings (
  id int primary key default 1,
  shop_name text not null default 'Marugen Koi Farm',
  shop_phone text,
  shop_address text,
  currency text not null default 'SGD',
  gst_percent int not null default 9,
  gst_included_in_price boolean not null default true,
  show_price_default boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.settings enable row level security;

create policy "Anyone can view settings"
  on public.settings for select using (true);

create policy "Admins can manage settings"
  on public.settings for all
  using (public.is_admin()) with check (public.is_admin());

insert into public.settings (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Storage bucket for product images
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

create policy "Anyone can view product images"
  on storage.objects for select
  using (bucket_id = 'product-images');

create policy "Admins can upload product images"
  on storage.objects for insert
  with check (bucket_id = 'product-images' and public.is_admin());

create policy "Admins can update product images"
  on storage.objects for update
  using (bucket_id = 'product-images' and public.is_admin());

create policy "Admins can delete product images"
  on storage.objects for delete
  using (bucket_id = 'product-images' and public.is_admin());
