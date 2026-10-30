-- Fixtures: customer, staff, one live code, one retired code, and two codes
-- that differ only by case (older rows created outside the admin screen).
insert into public.profiles(id, role) values
  ('00000000-0000-0000-0000-0000000000c1', 'customer'),
  ('00000000-0000-0000-0000-0000000000c2', 'customer'),
  ('00000000-0000-0000-0000-0000000000a1', 'staff');
insert into public.promo_codes(id, code, discount_type, discount_value, active, created_at) values
  ('00000000-0000-0000-0000-000000000101', 'SAVE10', 'percent', 10, true, now() - interval '3 days'),
  ('00000000-0000-0000-0000-000000000102', 'RETIRED', 'fixed', 5, false, now() - interval '3 days'),
  ('00000000-0000-0000-0000-000000000103', 'Dup', 'fixed', 1, true, now() - interval '2 days'),
  ('00000000-0000-0000-0000-000000000104', 'DUP', 'fixed', 2, true, now() - interval '1 day');
insert into public.orders(id, user_id, status) values
  ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-0000000000c2', 'paid');
insert into public.promo_code_redemptions(promo_code_id, user_id, order_id) values
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-0000000000c2',
   '00000000-0000-0000-0000-000000000201');

-- 1. Nobody outside admin can list codes through the table.
set role anon;
select set_config('request.jwt.claim.sub', '', false);
do $$ begin
  if (select count(*) from public.promo_codes) <> 0 then
    raise exception 'Anonymous caller can list promo codes';
  end if;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$ begin
  if (select count(*) from public.promo_codes) <> 0 then
    raise exception 'Customer can list promo codes';
  end if;
end $$;

-- 2. A customer checks only an exact code; wildcards match nothing.
do $$
declare
  v record;
begin
  if exists (select 1 from public.check_promo_code('%'))
     or exists (select 1 from public.check_promo_code('_AVE10'))
     or exists (select 1 from public.check_promo_code('SAVE%'))
     or exists (select 1 from public.check_promo_code('*'))
     or exists (select 1 from public.check_promo_code(''))
     or exists (select 1 from public.check_promo_code(null)) then
    raise exception 'Wildcard or empty input matched a promo code';
  end if;
  select * into strict v from public.check_promo_code('  save10 ');
  if v.code <> 'SAVE10' or v.discount_value <> 10 or v.already_redeemed then
    raise exception 'Exact case-insensitive check failed: %', row_to_json(v);
  end if;
  if exists (select 1 from public.check_promo_code('RETIRED')) then
    raise exception 'Inactive promo code exposed to a customer';
  end if;
  begin
    perform * from public.find_promo_code('SAVE10');
    raise exception 'Customer can call the server-only lookup';
  exception when insufficient_privilege then null;
  end;
end $$;

-- 3. A previous redemption is reported to that customer only.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', false);
do $$ begin
  if not (select already_redeemed from public.check_promo_code('SAVE10')) then
    raise exception 'Previous redemption not reported';
  end if;
end $$;

-- 4. Anonymous callers cannot use the checker at all.
set role anon;
select set_config('request.jwt.claim.sub', '', false);
do $$ begin
  begin
    perform * from public.check_promo_code('SAVE10');
    raise exception 'Anonymous caller can check promo codes';
  exception when insufficient_privilege then null;
  end;
end $$;

-- 5. Edge Functions resolve the same exact row, including retired codes
--    (they reject inactive ones themselves), deterministically.
set role service_role;
do $$ begin
  if (select code from public.find_promo_code('save10')) is distinct from 'SAVE10' then
    raise exception 'Server lookup is not case-insensitive';
  end if;
  if exists (select 1 from public.find_promo_code('%'))
     or exists (select 1 from public.find_promo_code('S*')) then
    raise exception 'Server lookup accepts wildcards';
  end if;
  if (select active from public.find_promo_code('retired')) is distinct from false then
    raise exception 'Server lookup hid an inactive code';
  end if;
  if (select code from public.find_promo_code('Dup')) is distinct from 'Dup' then
    raise exception 'Exact spelling did not win among case duplicates';
  end if;
  if (select code from public.find_promo_code('dup')) is distinct from 'DUP' then
    raise exception 'Newest code did not win among case duplicates';
  end if;
end $$;

-- 6. Admins still manage every code through the table.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$ begin
  if (select count(*) from public.promo_codes) <> 4 then
    raise exception 'Admin lost access to promo codes';
  end if;
  update public.promo_codes set active = true where code = 'RETIRED';
  if not found then raise exception 'Admin could not update a promo code'; end if;
end $$;
reset role;
