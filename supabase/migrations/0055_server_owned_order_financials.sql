-- Staff/owners may fulfill orders, but payment/refund truth belongs to
-- verified server endpoints. RLS granting admin UPDATE must not bypass it.
create or replace function public.guard_server_owned_order_financials()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  if new.status is distinct from old.status
     and new.status in ('paid', 'refunded') then
    raise exception 'Payment and refund status must be verified by the payment backend';
  end if;

  if new.total is distinct from old.total
     or new.user_id is distinct from old.user_id
     or new.idempotency_key is distinct from old.idempotency_key
     or new.promo_code is distinct from old.promo_code
     or new.discount_amount is distinct from old.discount_amount
     or new.stripe_refund_id is distinct from old.stripe_refund_id
     or new.refund_amount is distinct from old.refund_amount
     or new.refunded_at is distinct from old.refunded_at then
    raise exception 'Checkout financial records may only be changed by the payment backend';
  end if;
  return new;
end;
$$;

create trigger orders_server_owned_financials
  before update on public.orders
  for each row execute function public.guard_server_owned_order_financials();
