-- Cancellation must not release stock while a PaymentIntent can still succeed.
drop policy if exists "Users can cancel their own pending orders" on public.orders;
create or replace function public.guard_verified_payment_cancellation()
returns trigger language plpgsql set search_path=public as $$
begin
 -- The payment identity is immutable once linked. A status-only trigger
 -- permits clearing the link first, then cancelling in a second update.
 if new.stripe_payment_intent_id is distinct from old.stripe_payment_intent_id then
  if old.stripe_payment_intent_id is not null then
   raise exception 'An order PaymentIntent cannot be cleared or replaced';
  end if;
  if current_user not in ('postgres','supabase_admin','service_role') then
   raise exception 'Only the payment backend may link a PaymentIntent';
  end if;
 end if;
 if new.status='cancelled' and old.status is distinct from 'cancelled' then
  if old.status <> 'pending' then
   raise exception 'Paid or fulfilled orders require a refund, not cancellation';
  end if;
  if old.stripe_payment_intent_id is not null
     and current_user not in ('postgres','supabase_admin','service_role') then
   raise exception 'Payment cancellation must be verified server-side';
  end if;
 end if;
 return new;
end;
$$;
drop trigger if exists orders_verified_payment_cancellation on public.orders;
create trigger orders_verified_payment_cancellation before update of status, stripe_payment_intent_id on public.orders
for each row execute function public.guard_verified_payment_cancellation();
-- Cron may release only orphan reservations with no PaymentIntent.
-- Linked intents are reconciled/cancelled through Stripe by the Edge job.
create or replace function public.cancel_stale_pending_orders()
returns void language sql security definer set search_path=public as $$
 update public.orders set status='cancelled'
 where status='pending' and stripe_payment_intent_id is null
 and created_at < now()-interval '30 minutes';
$$;
