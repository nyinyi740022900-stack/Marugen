-- Marugen Koi Farm — push notification token storage.
-- Stores each user's current device FCM token on their profile so a
-- future server-side flow (e.g. "notify this user their order shipped")
-- has something to target. Run with: supabase db push
-- (or paste into the Supabase SQL editor)

alter table public.profiles
  add column if not exists fcm_token text;
