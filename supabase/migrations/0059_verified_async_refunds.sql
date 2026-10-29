-- Refund requests are not proof of money returned. Only verified Stripe
-- succeeded refunds contribute to refund_amount or complete an order.
begin;
alter table public.orders
  add column refund_status text check (refund_status in ('pending','requires_action','succeeded','failed','canceled','partially_refunded')),
  add column refund_pending_amount numeric not null default 0 check (refund_pending_amount >= 0),
  add column refund_failure_reason text;

create table public.payment_refunds (
  stripe_refund_id text primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  stripe_payment_intent_id text not null,
  amount_cents bigint not null check (amount_cents > 0),
  currency text not null check (currency='sgd'),
  status text not null check (status in ('pending','requires_action','succeeded','failed','canceled')),
  stripe_created_at timestamptz not null,
  failure_reason text,
  updated_at timestamptz not null default now(),
  observed_at timestamptz not null
);
create index payment_refunds_order_idx on public.payment_refunds(order_id);
alter table public.payment_refunds enable row level security;
revoke all on public.payment_refunds from public, anon, authenticated;
grant select, insert, update on public.payment_refunds to service_role;

create function public.guard_refund_summary() returns trigger language plpgsql set search_path=public as $$
begin
 if current_user not in ('postgres','supabase_admin','service_role') and
    (new.refund_status is distinct from old.refund_status or
     new.refund_pending_amount is distinct from old.refund_pending_amount or
     new.refund_failure_reason is distinct from old.refund_failure_reason) then
   raise exception 'Refund records may only be changed by the payment backend';
 end if;
 return new;
end $$;
create trigger orders_refund_summary_guard before update on public.orders
for each row execute function public.guard_refund_summary();

create function public.record_verified_refund(
 p_order_id uuid, p_intent_id text, p_refund_id text, p_amount_cents bigint,
 p_currency text, p_status text, p_created_at timestamptz, p_failure_reason text,
 p_observed_at timestamptz default clock_timestamp()
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
 o public.orders%rowtype;
 r public.payment_refunds%rowtype;
 successful bigint;
 pending bigint;
 summary text;
 latest_id text;
 failure text;
 newly_refunded boolean;
begin
 select * into o from public.orders where id=p_order_id for update;
 if not found or o.stripe_payment_intent_id is distinct from p_intent_id or
    o.status not in ('paid','packing','shipped','delivered','refunded') or
    p_amount_cents is null or p_amount_cents <= 0 or p_amount_cents > round(o.total*100) or
    p_currency is distinct from 'sgd' or p_refund_id is null or length(p_refund_id)=0 or
    p_status is null or p_status not in ('pending','requires_action','succeeded','failed','canceled') or
    p_created_at is null or p_observed_at is null then
   raise exception 'Invalid verified refund identity, amount, currency or state';
 end if;
 select * into r from public.payment_refunds where stripe_refund_id=p_refund_id;
 if found then
   if r.order_id <> p_order_id or r.stripe_payment_intent_id <> p_intent_id or
      r.amount_cents <> p_amount_cents or r.currency <> p_currency then
     raise exception 'Refund identity is immutable';
   end if;
   -- The server fetches current Stripe state even for old webhook events.
   -- Keep the newer API observation if concurrent requests finish out of order.
   -- Success may legitimately change to failed/requires_action after a bank return.
   if p_observed_at > r.observed_at then
     update public.payment_refunds set status=p_status,
       failure_reason=p_failure_reason, updated_at=now(), observed_at=p_observed_at
       where stripe_refund_id=p_refund_id;
   end if;
 else
   insert into public.payment_refunds values
     (p_refund_id,p_order_id,p_intent_id,p_amount_cents,p_currency,p_status,p_created_at,p_failure_reason,now(),p_observed_at);
 end if;
 select coalesce(sum(amount_cents) filter(where status='succeeded'),0),
        coalesce(sum(amount_cents) filter(where status in ('pending','requires_action')),0)
 into successful,pending from public.payment_refunds where order_id=p_order_id;
 if successful+pending > round(o.total*100) then raise exception 'Refunds exceed order total'; end if;
 summary := case
   when successful=round(o.total*100) then 'succeeded'
   when exists(select 1 from public.payment_refunds where order_id=p_order_id and status='requires_action') then 'requires_action'
   when pending>0 then 'pending'
   when successful>0 then 'partially_refunded'
   when exists(select 1 from public.payment_refunds where order_id=p_order_id and status='failed') then 'failed'
   else 'canceled' end;
 select stripe_refund_id into latest_id from public.payment_refunds where order_id=p_order_id
 order by stripe_created_at desc,stripe_refund_id desc limit 1;
 select failure_reason into failure from public.payment_refunds where order_id=p_order_id and status='failed'
 order by stripe_created_at desc,stripe_refund_id desc limit 1;
 newly_refunded := summary='succeeded' and o.status<>'refunded';
 update public.orders set
   status=case when summary='succeeded' then 'refunded' else status end,
   stripe_refund_id=latest_id, refund_status=summary,
   refund_amount=successful::numeric/100, refund_pending_amount=pending::numeric/100,
   refund_failure_reason=case when summary='failed' then failure else null end,
   refunded_at=case when summary='succeeded' then coalesce(refunded_at,now()) else null end
 where id=p_order_id;
 return jsonb_build_object('refundId',latest_id,'refundStatus',summary,
   'amount',successful::numeric/100,'pendingAmount',pending::numeric/100,'newlyRefunded',newly_refunded);
end $$;
revoke all on function public.record_verified_refund(uuid,text,text,bigint,text,text,timestamptz,text,timestamptz) from public,anon,authenticated;
grant execute on function public.record_verified_refund(uuid,text,text,bigint,text,text,timestamptz,text,timestamptz) to service_role;
comment on column public.orders.refund_amount is 'Sum of verified succeeded Stripe refunds in SGD; excludes pending and failed requests.';
comment on column public.orders.refund_pending_amount is 'Verified Stripe refunds still pending or requiring action, in SGD.';
commit;
