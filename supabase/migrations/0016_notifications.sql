-- Marugen Koi Farm — 0016: in-app notification inbox.
-- Run with: supabase db push   (or paste into the Supabase SQL editor)
--
-- Push notifications (FCM) only reach a device that's set up to receive
-- them — and even then, a push the user swipes away or that arrives while
-- the app is closed leaves nothing to look back at (foreground pushes
-- today just flash a SnackBar, see PushNotificationService). This table
-- gives both customers and admins a durable, in-app list of everything
-- that was sent to them, independent of whether the FCM push itself was
-- ever configured or delivered.
--
-- Written exclusively by send-order-notification (service-role client,
-- bypasses RLS) for every recipient it resolves — a row lands here even
-- when FCM_SERVICE_ACCOUNT_JSON isn't set yet, so the inbox works from
-- day one regardless of Firebase setup.

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text not null,
  -- Nullable + on delete set null: the notification is still meaningful
  -- history even if the order it referenced is later hard-deleted (never
  -- happens today, but no reason to cascade-delete a customer's own
  -- notification history over it).
  order_id uuid references public.orders (id) on delete set null,
  -- 'order_status' (paid/shipped/delivered/cancelled, sent to the
  -- customer) or 'admin_alert' (out_for_delivery etc., sent to staff/owner).
  type text not null default 'order_status',
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_id_created_at_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

create policy "Users can view their own notifications"
  on public.notifications for select using (auth.uid() = user_id);

-- Only the "read" flag is ever meant to change client-side (tapping a
-- notification marks it read); nothing writes any other column after
-- insert, but RLS here doesn't need to police that column-by-column —
-- a user editing their own notification's text harms nobody but
-- themselves, same trust level as other self-owned rows in this schema.
create policy "Users can mark their own notifications read"
  on public.notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- No insert policy: rows are only ever written by send-order-notification
-- using the service-role key, which bypasses RLS entirely — same pattern
-- as promo_code_redemptions (0015_promo_code_limits.sql).
