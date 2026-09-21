-- Replaces the narrow terminal-only guard (0028) with a full forward-only
-- state machine, mirroring `validNextStatuses()` in lib/shared/models/
-- order.dart exactly — so the same rule holds whether the write comes
-- from the admin app's UI (which now only offers valid next-status
-- buttons) or a direct API call that bypasses it entirely.
--
-- Graph (identical to the Dart helper):
--   pending   -> paid, cancelled
--   paid      -> packing, shipped, delivered, cancelled, refunded
--   packing   -> shipped, delivered, cancelled, refunded
--   shipped   -> delivered, refunded
--   delivered -> refunded
--   cancelled, refunded -> (nothing; terminal)
--
-- paid/packing can jump straight to delivered because live-fish orders
-- are hand-delivered by the shop with no courier "shipped" step (see
-- admin_delivery_screen.dart's "Delivered by shop" action). A no-op
-- write (new.status = old.status, e.g. qxpress-shipment re-setting
-- 'shipped' on an already-shipped order) is always allowed.
--
-- Also adds an audit trail: every real status change is recorded in
-- order_status_history, since previously a status change was a silent
-- overwrite with no record of what happened or when — useful for
-- resolving "why does this order say X" support questions.

drop trigger if exists orders_status_terminal_guard on public.orders;
drop function if exists public.enforce_order_status_terminal();

create or replace function public.enforce_order_status_forward_only()
returns trigger
language plpgsql
as $$
declare
  allowed text[];
begin
  if new.status = old.status then
    return new;
  end if;

  allowed := case old.status
    when 'pending' then array['paid', 'cancelled']
    when 'paid' then array['packing', 'shipped', 'delivered', 'cancelled', 'refunded']
    when 'packing' then array['shipped', 'delivered', 'cancelled', 'refunded']
    when 'shipped' then array['delivered', 'refunded']
    when 'delivered' then array['refunded']
    else array[]::text[] -- cancelled, refunded: terminal
  end;

  if not (new.status = any(allowed)) then
    raise exception 'Invalid order status transition: % -> %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger orders_status_forward_only_guard
  before update of status on public.orders
  for each row
  execute function public.enforce_order_status_forward_only();

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  from_status text not null,
  to_status text not null,
  -- null for a service-role write (Stripe/17TRACK webhooks, stale-order
  -- cleanup) — those requests carry no user JWT, so auth.uid() is null.
  changed_by uuid references public.profiles (id),
  changed_at timestamptz not null default now()
);

create index if not exists order_status_history_order_id_idx
  on public.order_status_history (order_id, changed_at desc);

alter table public.order_status_history enable row level security;

create policy "Admins can view order status history"
  on public.order_status_history for select using (public.is_admin());

create policy "Users can view their own orders' status history"
  on public.order_status_history for select
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and o.user_id = auth.uid()
  ));

-- No insert policy: only written by the trigger below (as the table
-- owner), same pattern as notifications (0016_notifications.sql).

create or replace function public.log_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by)
    values (new.id, old.status, new.status, auth.uid());
  end if;
  return new;
end;
$$;

create trigger orders_status_history_log
  after update of status on public.orders
  for each row
  execute function public.log_order_status_change();
