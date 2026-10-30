-- Marugen Koi Farm — 0071: private promo codes.
--
-- 0006 let anyone (including the anon key bundled in the app) SELECT every
-- active promo code, so `GET /rest/v1/promo_codes` listed them all. Lookups
-- also used ILIKE, where `%`, `_` and PostgREST's `*` are wildcards: typing
-- `%` applied the only active code without knowing it.
--
-- Codes are now readable only by admins. Customers check one exact code
-- (case-insensitive) through check_promo_code; Edge Functions resolve the
-- same row through find_promo_code, so the app and the server always agree.

drop policy if exists "Anyone can check an active promo code" on public.promo_codes;

-- Exact, case-insensitive match. Admin-created codes are upper case, but
-- older rows may differ only by case, so the pick is deterministic: active
-- first, then the exact spelling, then the newest.
create or replace function public.find_promo_code(p_code text)
returns setof public.promo_codes
language sql
stable
set search_path = public, pg_temp
as $$
  select p.*
    from public.promo_codes p
   where btrim(coalesce(p_code, '')) <> ''
     and lower(p.code) = lower(btrim(p_code))
   order by p.active desc, (p.code = btrim(p_code)) desc, p.created_at desc, p.id
   limit 1;
$$;

revoke all on function public.find_promo_code(text) from public, anon, authenticated;
grant execute on function public.find_promo_code(text) to service_role;

-- Customer checkout: one active code the caller already knows, plus whether
-- they have used it before (create-payment-intent rejects a second use).
create or replace function public.check_promo_code(p_code text)
returns table (
  id uuid,
  code text,
  discount_type text,
  discount_value numeric,
  active boolean,
  expires_at timestamptz,
  max_redemptions int,
  times_redeemed int,
  already_redeemed boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id, p.code, p.discount_type, p.discount_value, p.active,
         p.expires_at, p.max_redemptions, p.times_redeemed,
         exists (
           select 1
             from public.promo_code_redemptions r
            where r.promo_code_id = p.id
              and r.user_id = auth.uid()
         )
    from public.find_promo_code(p_code) p
   where p.active
     and auth.uid() is not null;
$$;

revoke all on function public.check_promo_code(text) from public, anon;
grant execute on function public.check_promo_code(text) to authenticated;
