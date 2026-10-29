-- Exercises 0069_release_promo_on_refund.sql. Any failed check raises.
do $$
declare
  promo uuid := '00000000-0000-0000-0000-0000000000a2';
  buyer uuid := '00000000-0000-0000-0000-0000000000c2';
  o uuid := '00000000-0000-0000-0000-0000000000b2';
begin
  if (select times_redeemed from public.promo_codes where code='OLD') <> 0
     or exists(select 1 from public.promo_code_redemptions where order_id='00000000-0000-0000-0000-0000000000b1') then
    raise exception 'Backfill did not free the already-refunded order';
  end if;

  -- paid -> refunded frees the slot and the customer's one use.
  insert into public.promo_codes values (promo,'MARUGRN2026',1,1);
  insert into public.orders values (o,'paid','MARUGRN2026');
  insert into public.promo_code_redemptions(promo_code_id,user_id,order_id) values (promo,buyer,o);
  -- Renaming the code after use must not leak the slot.
  update public.promo_codes set code='MARUGEN2026' where id=promo;
  update public.orders set status='refunded' where id=o;
  if (select times_redeemed from public.promo_codes where id=promo) <> 0 then
    raise exception 'Refund did not release the promo slot';
  end if;
  if exists(select 1 from public.promo_code_redemptions where order_id=o) then
    raise exception 'Refund did not let the customer reuse the code';
  end if;

  -- cancelled -> refunded releases exactly once.
  update public.orders set status='paid' where id=o;
  update public.promo_codes set times_redeemed=1 where id=promo;
  insert into public.promo_code_redemptions(promo_code_id,user_id,order_id) values (promo,buyer,o);
  update public.orders set status='cancelled' where id=o;
  update public.orders set status='refunded' where id=o;
  if (select times_redeemed from public.promo_codes where id=promo) <> 0 then
    raise exception 'Cancel then refund changed the count more than once';
  end if;

  -- Other status changes keep the redemption.
  update public.orders set status='paid' where id=o;
  update public.promo_codes set times_redeemed=1 where id=promo;
  insert into public.promo_code_redemptions(promo_code_id,user_id,order_id) values (promo,buyer,o);
  update public.orders set status='shipped' where id=o;
  update public.orders set status='delivered' where id=o;
  if (select times_redeemed from public.promo_codes where id=promo) <> 1 then
    raise exception 'A fulfilled order lost its redemption';
  end if;
end $$;
