-- Marugen Koi Farm — 0069: free a promo code when its order is refunded.
--
-- 0015 only released a redemption when an order became `cancelled`. A
-- refund moves an order straight from paid/packing/shipped/delivered to
-- `refunded` (0059), so the customer kept the "already used" mark and the
-- code kept its slot under max_redemptions. 0015 also matched the code by
-- its current text, so renaming a code after it was used leaked the slot.
--
-- Now: an order leaving the live states for `cancelled` or `refunded`
-- deletes its redemption row and decrements the exact promo it points to.
-- Deleting the row first makes the release happen at most once per order,
-- so cancelled -> refunded never decrements twice.
begin;

create or replace function public.restore_promo_on_cancel()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.status in ('cancelled', 'refunded')
     and old.status not in ('cancelled', 'refunded') then
    with released as (
      delete from public.promo_code_redemptions
       where order_id = new.id
      returning promo_code_id
    )
    update public.promo_codes p
       set times_redeemed = greatest(0, p.times_redeemed - 1)
      from released r
     where p.id = r.promo_code_id;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_restore_promo_on_cancel on public.orders;
create trigger orders_restore_promo_on_cancel
  after update of status on public.orders
  for each row execute function public.restore_promo_on_cancel();

-- Repair orders refunded before this migration: they still hold a slot.
with released as (
  delete from public.promo_code_redemptions pr
   using public.orders o
   where o.id = pr.order_id
     and o.status in ('cancelled', 'refunded')
  returning pr.promo_code_id
), counts as (
  select promo_code_id, count(*) as n from released group by promo_code_id
)
update public.promo_codes p
   set times_redeemed = greatest(0, p.times_redeemed - c.n)
  from counts c
 where p.id = c.promo_code_id;

commit;
