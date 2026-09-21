-- Adds a customer-uploadable profile photo.
--
-- `avatar_url` is a plain column on profiles — "Users can update their
-- own profile" (0001_init.sql) already covers writing it, no RLS change
-- needed there.
--
-- Storage: reuses the existing `product-images` bucket (public-read,
-- admin-only write per 0001_init.sql's original policies) rather than a
-- new bucket — but those original insert/update/delete policies check
-- `public.is_admin()`, which would block every regular customer from
-- uploading their own avatar. The three policies below add a narrow
-- exception: any authenticated user may write ONLY under
-- `avatars/<their own auth.uid()>/...` in the same bucket, leaving the
-- admin-only restriction on every other path (`products/`, `varieties/`,
-- etc.) exactly as it was.

alter table public.profiles add column if not exists avatar_url text;

create policy "Users can upload their own avatar"
  on storage.objects for insert
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = 'avatars'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "Users can update their own avatar"
  on storage.objects for update
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = 'avatars'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "Users can delete their own avatar"
  on storage.objects for delete
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = 'avatars'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
