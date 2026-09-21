-- Adds a minimal state-machine guard on orders.status: an order that has
-- reached a terminal state (cancelled/refunded) can never move to any
-- other status again. Fixes the "Admins can update orders" RLS policy
-- (0001_init.sql) having no with-check at all on status transitions — the
-- admin UI's status dropdown (admin_orders_screen.dart) currently lets
-- staff pick any of the 7 statuses from any current status with zero
-- restriction, so a misclick (or a compromised/buggy admin client) could
-- resurrect a cancelled/refunded order.
--
-- Deliberately narrow rather than a full transition whitelist: no
-- legitimate code path in this app (customer cancel, stripe-webhook,
-- qxpress-shipment, track-register, track-webhook, stale-order cleanup,
-- or any admin action) ever moves an order OUT of cancelled/refunded, so
-- this cannot break a real flow — it only closes the one transition that
-- was always a mistake. A trigger (not a table CHECK/RLS with-check) is
-- used because only a trigger can compare OLD vs NEW in one place, and it
-- applies to every writer (including service-role Edge Functions), which
-- is correct here since none of them ever needs this transition either.

create or replace function public.enforce_order_status_terminal()
returns trigger
language plpgsql
as $$
begin
  if old.status in ('cancelled', 'refunded') and new.status is distinct from old.status then
    raise exception 'Order % is already %; status cannot be changed further', old.id, old.status;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_status_terminal_guard on public.orders;
create trigger orders_status_terminal_guard
  before update of status on public.orders
  for each row
  execute function public.enforce_order_status_terminal();
