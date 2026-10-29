-- Owner-requested order cleanup. Run only after final irreversible-delete confirmation.
-- Backup: output/backups/orders-before-cleanup-2026-10-24.json
-- No Stripe/courier API call, refund, cancellation or stock adjustment.
begin;
lock table public.orders, public.order_items, public.notifications,
 public.order_status_history, public.promo_code_redemptions,
 public.order_parcels, public.payment_refunds in share row exclusive mode;
create temp table cleanup_targets(id uuid primary key) on commit drop;
insert into cleanup_targets select unnest(array['16816d05-8e56-4f9d-83d3-61ff0c99261e'::uuid,'348c7b85-1b99-4891-9776-adc3cc36268f'::uuid,'4b5eb1ca-ed49-4460-b578-ae74e3e1731b'::uuid,'589e5419-92f6-48df-8b80-c4ae1c664134'::uuid,'67350a85-8d01-472f-8029-e0f773643186'::uuid,'752ce0ad-d797-4f6b-83be-f87e5915e8c9'::uuid,'867e3d8e-99d6-4f35-9b14-d36b9f06e6e6'::uuid,'8af7b051-d3d5-4665-92ae-2a76ca2cead8'::uuid,'984efa04-a619-4611-88ed-14368a6443c8'::uuid,'a0622761-673c-4ec7-8438-a17cfea8d298'::uuid,'a1dc9b8b-2301-462f-b680-27539a18a2f1'::uuid,'b2799bce-deb3-4c6b-bff0-c172c3cf5a7a'::uuid,'c2c49069-aabb-4364-bf65-0f4cf328710a'::uuid,'d10ccae4-5b32-4377-9bcd-55d15713d94f'::uuid,'d162be8f-4d3d-4e66-b811-21046835b1ba'::uuid,'d6c1e48a-8540-49ac-b4af-036bd312417e'::uuid,'e8d8e9cd-dc18-4eeb-b77b-407ff5d35832'::uuid,'edeed1f7-c9ed-4755-850e-d24894627ef9'::uuid,'ee59e508-de82-41d9-8d10-36c454e18c4e'::uuid]);
do $$
declare
 keep_id constant uuid := '06806c1f-348e-439a-9d8e-eb0194edd2f7';
 keep_before jsonb; keep_after jsonb; removed integer;
 related_table text;
begin
 if (select count(*) from public.orders where id=keep_id and order_number='19102026-0001'
     and qxpress_tracking_no='QSP223261096')<>1 then
  raise exception 'Protected real order not exactly identified';
 end if;
 if (select count(*) from public.orders where id<>keep_id)<>19 or
    (select count(*) from public.orders o join cleanup_targets t using(id))<>19 then
  raise exception 'Order scope changed; inspect again';
 end if;
 if (select count(*) from public.order_items i join cleanup_targets t on t.id=i.order_id)<>33 or
    (select count(*) from public.order_status_history h join cleanup_targets t on t.id=h.order_id)<>26 or
    exists(select 1 from public.order_parcels p join cleanup_targets t on t.id=p.order_id) or
    exists(select 1 from public.payment_refunds r join cleanup_targets t on t.id=r.order_id) or
    exists(select 1 from public.promo_code_redemptions r join cleanup_targets t on t.id=r.order_id) then
  raise exception 'Dependent record scope changed; inspect again';
 end if;
 select to_jsonb(o) into strict keep_before from public.orders o where id=keep_id;
 create temp table cleanup_preserved(table_name text primary key, data jsonb) on commit drop;
 foreach related_table in array array['order_items','notifications','order_status_history',
   'promo_code_redemptions','order_parcels','payment_refunds'] loop
  execute format('insert into cleanup_preserved select %L, coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text), ''[]''::jsonb) from public.%I t where order_id=$1',related_table,related_table) using keep_id;
 end loop;
 delete from public.notifications n using cleanup_targets t where n.order_id=t.id;
 get diagnostics removed = row_count;
 if removed<>23 then raise exception 'Notification scope changed'; end if;
 delete from public.orders o using cleanup_targets t where o.id=t.id;
 get diagnostics removed = row_count;
 if removed<>19 then raise exception 'Unexpected deleted order count'; end if;
 select to_jsonb(o) into strict keep_after from public.orders o where id=keep_id;
 if keep_before is distinct from keep_after or (select count(*) from public.orders)<>1 then
  raise exception 'Protected order changed or unexpected orders remain';
 end if;
 foreach related_table in array array['order_items','notifications','order_status_history',
   'promo_code_redemptions','order_parcels','payment_refunds'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text), ''[]''::jsonb) from public.%I t where order_id=$1',related_table) into keep_after using keep_id;
  if keep_after is distinct from (select p.data from cleanup_preserved p where p.table_name=related_table) then
   raise exception 'Protected dependent records changed: %',related_table;
  end if;
 end loop;
end $$;
select order_number,status,qxpress_tracking_no,(select count(*) from public.orders) as remaining_orders
from public.orders;
commit;
