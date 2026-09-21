-- One-off cleanup: delete "Kohaku Koi #1" and "Premium Fish Food 1kg"
-- plus related wishlist / reviews / variants / order history that
-- referenced them.
--
-- Run in Supabase SQL Editor. Safe to re-run.

begin;

create temporary table _purge_products on commit drop as
select id, name
from public.products
where name in (
  'Kohaku Koi #1',
  'Premium Fish Food 1kg'
);

-- Orders that contain any of these products (or their variants)
create temporary table _purge_orders on commit drop as
select distinct oi.order_id as id
from public.order_items oi
where oi.product_id in (select id from _purge_products)
   or oi.variant_id in (
        select v.id
        from public.product_variants v
        where v.product_id in (select id from _purge_products)
      );

-- Notifications pointing at those orders
delete from public.notifications
where order_id in (select id from _purge_orders);

-- Cascades: order_items, promo_code_redemptions
delete from public.orders
where id in (select id from _purge_orders);

-- Cascades: product_variants, wishlist_items, product_reviews
delete from public.products
where id in (select id from _purge_products);

commit;

-- Verify
select name from public.products
where name in ('Kohaku Koi #1', 'Premium Fish Food 1kg');
-- expect 0 rows
