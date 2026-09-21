-- Fixes a bug in the 0029 idempotency migration: a PARTIAL unique index
-- (`where order_id is not null`) cannot be targeted by supabase-js's
-- `.upsert(data, {onConflict: 'order_id,user_id,key'})` — Postgres
-- requires the ON CONFLICT target to explicitly restate a partial index's
-- WHERE clause, which supabase-js's upsert helper has no way to pass.
-- Every upsert call in send-order-notification has been failing since
-- 0029 with "there is no unique or exclusion constraint matching the ON
-- CONFLICT specification" (Postgres error 42P10), silently breaking the
-- in-app notification inbox for every order status change (confirmed via
-- Edge Function logs: consistent 42P10 on every invocation).
--
-- Dropping the partial predicate is behavior-neutral: Postgres already
-- treats every NULL as distinct in a unique index, so rows with
-- order_id IS NULL were never going to collide with each other or with
-- non-null rows regardless of the WHERE clause — the partial predicate
-- was unnecessary defensiveness, not a behavior requirement.
drop index if exists public.notifications_order_user_key_uidx;

create unique index if not exists notifications_order_user_key_uidx
  on public.notifications (order_id, user_id, key);
