-- Wipe ALL order history (and order-linked notifications / promo redemptions).
-- Does NOT delete products, variants, wishlist, or reviews.
--
-- Cascades from orders:
--   • order_items              (ON DELETE CASCADE)
--   • promo_code_redemptions   (ON DELETE CASCADE)
-- notifications.order_id is ON DELETE SET NULL — we hard-delete
-- order-related notification rows below so the inbox is clean too.
--
-- Run in Supabase SQL Editor. Destructive — no undo.

begin;

-- Order-linked inbox rows (type order_status / admin_alert with an order)
delete from public.notifications
where order_id is not null
   or type in ('order_status', 'admin_alert');

-- Promo redemptions cascade with orders, but delete explicitly first
-- in case any orphan rows exist.
delete from public.promo_code_redemptions;

-- order_items cascade from orders
delete from public.orders;

commit;

-- Verify (all should be 0)
select
  (select count(*) from public.orders) as orders,
  (select count(*) from public.order_items) as order_items,
  (select count(*) from public.promo_code_redemptions) as promo_redemptions,
  (select count(*) from public.notifications
     where order_id is not null
        or type in ('order_status', 'admin_alert')) as order_notifications;
