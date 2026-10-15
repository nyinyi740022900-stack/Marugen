-- A retry key belongs to the entire checkout attempt. Paying/refunding an
-- order must not permit the same request to create a second charge.
-- A key can be reused only after the previous attempt is cancelled through
-- the verified backend path enforced by migration 0053.
-- Historical duplicates must be investigated, never silently rewritten.
do $$
declare duplicate_groups bigint;
begin
  select count(*) into duplicate_groups from (
    select user_id, idempotency_key from public.orders
     where user_id is not null and idempotency_key is not null
       and status <> 'cancelled'
     group by user_id, idempotency_key having count(*) > 1
  ) duplicates;
  if duplicate_groups > 0 then
    raise exception 'Checkout idempotency migration blocked: % duplicate non-cancelled checkout key groups', duplicate_groups
      using errcode = '23505',
      hint = 'Investigate orders grouped by user_id and idempotency_key with status <> cancelled before retrying. No historical orders have been changed.';
  end if;
end;
$$;

-- Create the stronger index before removing the existing pending-only one.
-- If validation/index creation fails, the old protection remains available.
create unique index orders_user_checkout_idempotency_key_uidx
  on public.orders (user_id, idempotency_key)
  where idempotency_key is not null and status <> 'cancelled';
drop index if exists public.orders_user_pending_idempotency_key_uidx;
