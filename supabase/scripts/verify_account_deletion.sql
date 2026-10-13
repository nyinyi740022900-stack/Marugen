-- Disposable, transaction-only fixtures. ROLLBACK leaves no account/order changes.
begin;
do $$
declare
  test_user uuid := gen_random_uuid();
  test_order uuid := gen_random_uuid();
  test_promo uuid := gen_random_uuid();
  connection_present boolean;
begin
  if not exists(select 1 from supabase_migrations.schema_migrations where version='0051') then
    raise exception 'Migration 0051 is missing';
  end if;
  insert into auth.users(id,email,raw_user_meta_data)
    values(test_user,'privacy-validation-' || test_user || '@marugen.invalid','{}');
  insert into public.addresses(user_id,recipient_name,phone,line1,postal_code)
    values(test_user,'Disposable privacy fixture','00000000','Test address','000000');
  insert into public.orders(id,user_id,total,shipping_address)
    values(test_order,test_user,0,'{"recipient_name":"Disposable privacy fixture"}');
  insert into public.promo_codes(id,code,discount_type,discount_value,active,times_redeemed)
    values(test_promo,'PRIVACY-' || test_user,'fixed',1,false,1);
  insert into public.promo_code_redemptions(promo_code_id,user_id,order_id)
    values(test_promo,test_user,test_order);
  insert into public.order_status_history(order_id,from_status,to_status,changed_by)
    values(test_order,'pending','paid',test_user);
  select exists(select 1 from public.easyparcel_connection where id=1) into connection_present;
  if connection_present then
    update public.easyparcel_connection set connected_by=test_user where id=1;
  end if;
  -- The only user deleted is the UUID inserted above, inside this rollback.
  delete from auth.users where id=test_user;
  if exists(select 1 from public.profiles where id=test_user)
     or exists(select 1 from public.addresses where user_id=test_user) then
    raise exception 'Personal data did not cascade';
  end if;
  if not exists(select 1 from public.orders where id=test_order and user_id is null and total=0) then
    raise exception 'Order was lost or customer reference not detached';
  end if;
  if not exists(select 1 from public.promo_code_redemptions where order_id=test_order and user_id is null)
     or not exists(select 1 from public.promo_codes where id=test_promo and times_redeemed=1) then
    raise exception 'Promo audit/count was not preserved';
  end if;
  if exists(select 1 from public.order_status_history where order_id=test_order and changed_by is not null) then
    raise exception 'Audit actor was not detached';
  end if;
  if connection_present and exists(select 1 from public.easyparcel_connection where id=1 and connected_by is not null) then
    raise exception 'Connection actor was not detached';
  end if;
end $$;
select 'PASS: disposable auth deletion preserves business records and removes personal rows; fixtures rolled back' as result;
rollback;
