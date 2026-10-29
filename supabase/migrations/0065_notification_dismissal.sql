-- Recoverable inbox dismissal. No notification or order is physically deleted.
-- Existing own-row UPDATE policy also authorizes dismissal and Undo; keep
-- dismissed rows SELECT-visible to their owner so UPDATE/Undo works under RLS.
alter table public.notifications
  add column if not exists dismissed_at timestamptz;

comment on column public.notifications.dismissed_at is
  'Inbox dismissal batch timestamp; NULL means visible. Undo matches the exact timestamp.';

create index if not exists notifications_visible_user_created_at_idx
  on public.notifications (user_id, created_at desc)
  where dismissed_at is null;
