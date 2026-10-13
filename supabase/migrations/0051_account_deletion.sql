-- Retain necessary business records without keeping the customer's auth account.
-- No existing account or order is deleted by this migration.
alter table public.orders alter column user_id drop not null;
alter table public.orders drop constraint orders_user_id_fkey;
alter table public.orders add constraint orders_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;
alter table public.promo_code_redemptions alter column user_id drop not null;
alter table public.promo_code_redemptions drop constraint promo_code_redemptions_user_id_fkey;
alter table public.promo_code_redemptions add constraint promo_code_redemptions_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;
alter table public.order_status_history drop constraint order_status_history_changed_by_fkey;
alter table public.order_status_history add constraint order_status_history_changed_by_fkey
  foreign key (changed_by) references public.profiles(id) on delete set null;
alter table public.easyparcel_connection drop constraint easyparcel_connection_connected_by_fkey;
alter table public.easyparcel_connection add constraint easyparcel_connection_connected_by_fkey
  foreign key (connected_by) references public.profiles(id) on delete set null;

-- An old access JWT must not recreate an avatar after its profile is deleted.
alter policy "Users can upload their own avatar" on storage.objects with check (
  bucket_id = 'product-images'
  and (storage.foldername(name))[1] = 'avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
  and exists(select 1 from public.profiles where id = auth.uid())
);
alter policy "Users can update their own avatar" on storage.objects using (
  bucket_id = 'product-images'
  and (storage.foldername(name))[1] = 'avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
  and exists(select 1 from public.profiles where id = auth.uid())
) with check (
  bucket_id = 'product-images'
  and (storage.foldername(name))[1] = 'avatars'
  and (storage.foldername(name))[2] = auth.uid()::text
  and exists(select 1 from public.profiles where id = auth.uid())
);
