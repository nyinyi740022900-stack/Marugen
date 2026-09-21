-- Fixes duplicate notifications/pushes on a retried call to
-- send-order-notification (e.g. stripe-webhook or track-webhook retrying
-- after a network blip, or 17TRACK re-delivering the same webhook event).
-- Previously there was no way to tell "already notified this
-- order+recipient for this status/event" from "genuinely new", so a retry
-- inserted a second inbox row and sent a second push for the same event.
--
-- `key` captures the status/event string that drove the notification
-- ('paid' | 'shipped' | 'delivered' | 'cancelled' | 'out_for_delivery')
-- — see send-order-notification/index.ts, which now upserts on this
-- constraint with ignoreDuplicates so a retry is a no-op instead of a
-- second row + second push.

alter table public.notifications add column if not exists key text;

-- Backfill existing rows so the column can be made not null: best-effort
-- guess from title text for historical rows (new rows always set this
-- explicitly from the edge function going forward).
update public.notifications set key = case
  when title = 'Order confirmed' then 'paid'
  when title = 'Order shipped' then 'shipped'
  when title = 'Order delivered' then 'delivered'
  when title = 'Order cancelled' then 'cancelled'
  when title = 'Out for delivery' then 'out_for_delivery'
  else 'legacy_' || id::text
end
where key is null;

alter table public.notifications alter column key set not null;

-- Real production data already had exact duplicates (same order+recipient
-- notified twice for the same status, e.g. two "shipped" pushes for one
-- order/user) — this is direct evidence of the bug this migration fixes.
-- Keep the oldest row per (order_id, user_id, key) group and drop the
-- rest before the unique index below, or its creation fails.
delete from public.notifications n
using (
  select id,
         row_number() over (
           partition by order_id, user_id, key
           order by created_at asc, id asc
         ) as rn
  from public.notifications
  where order_id is not null
) d
where n.id = d.id and d.rn > 1;

create unique index if not exists notifications_order_user_key_uidx
  on public.notifications (order_id, user_id, key)
  where order_id is not null;
