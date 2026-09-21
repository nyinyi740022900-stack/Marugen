-- Per-user push-notification opt-in/out (Profile → Notifications toggle).
-- The in-app notification inbox always logs order updates regardless —
-- this only gates whether a push is actually sent to the device.
alter table public.profiles
  add column if not exists notifications_enabled boolean not null default true;
