-- Home-screen hero banner carousel.
--
-- Admin-managed slides shown at the top of the Shop tab: image, optional
-- headline/subtitle/button label, a tap target (an in-app path such as
-- /product/<id> or an https URL) and an optional schedule. The once-a-day
-- promo popup in `settings` stays as it is; this is the always-visible
-- carousel.
--
-- Customers only ever see rows that are active and inside their window;
-- the schedule is enforced here, not in the app, so an expired slide can
-- never be fetched by an old build.

create table if not exists public.home_banners (
  id uuid primary key default gen_random_uuid(),
  image_url text not null check (btrim(image_url) <> ''),
  title text check (title is null or length(title) <= 80),
  subtitle text check (subtitle is null or length(subtitle) <= 140),
  cta_label text check (cta_label is null or length(cta_label) <= 30),
  link_url text check (link_url is null or length(link_url) <= 2048),
  sort_order int not null default 0,
  active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint home_banners_window check (
    starts_at is null or ends_at is null or ends_at > starts_at
  )
);

create index if not exists home_banners_live_idx
  on public.home_banners (sort_order)
  where active;

alter table public.home_banners enable row level security;

-- Live = active and inside the window. Null bounds are open-ended.
create or replace function public.home_banner_is_live(
  p_active boolean,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns boolean
language sql
stable
as $$
  select p_active
     and (p_starts_at is null or p_starts_at <= now())
     and (p_ends_at is null or p_ends_at > now());
$$;

drop policy if exists "Anyone can view live home banners" on public.home_banners;
create policy "Anyone can view live home banners"
  on public.home_banners for select
  using (public.home_banner_is_live(active, starts_at, ends_at));

drop policy if exists "Admins can view all home banners" on public.home_banners;
create policy "Admins can view all home banners"
  on public.home_banners for select using (public.is_admin());

drop policy if exists "Admins can manage home banners" on public.home_banners;
create policy "Admins can manage home banners"
  on public.home_banners for all
  using (public.is_admin()) with check (public.is_admin());

grant select on public.home_banners to anon, authenticated;
grant insert, update, delete on public.home_banners to authenticated;

create or replace function public.touch_home_banner_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists home_banners_touch_updated_at on public.home_banners;
create trigger home_banners_touch_updated_at
  before update on public.home_banners
  for each row execute function public.touch_home_banner_updated_at();
