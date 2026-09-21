-- Enables Supabase Realtime (Postgres Changes) for the notifications
-- table, so the in-app bell/inbox updates the instant
-- send-order-notification inserts a row, instead of only on manual
-- pull-to-refresh. RLS's existing "Users can view their own
-- notifications" policy (0016_notifications.sql) is enforced the same way
-- for Realtime subscriptions as for normal selects, so this doesn't widen
-- who can see what — it's purely a delivery-timing change.
alter publication supabase_realtime add table public.notifications;
