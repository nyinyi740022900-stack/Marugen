-- Allow admins to delete a product that has been ordered.
--
-- order_items keeps its own snapshot (product_name, unit_price, quantity,
-- variant/size labels), so order history, invoices and totals survive.
-- Previously the default NO ACTION foreign keys made any delete of an
-- ordered product fail with 23503 (and order_items.variant_id blocked the
-- product_variants cascade). Detached items already have no stock to
-- restore: cancellation/stock logic skips rows whose product_id is null,
-- and the 0052 insert trigger accepts detached historical snapshots.
-- Reviews and wishlist rows still cascade with the product (0004/0005).

alter table public.order_items
  drop constraint if exists order_items_product_id_fkey,
  add constraint order_items_product_id_fkey
    foreign key (product_id) references public.products (id)
    on delete set null;

alter table public.order_items
  drop constraint if exists order_items_variant_id_fkey,
  add constraint order_items_variant_id_fkey
    foreign key (variant_id) references public.product_variants (id)
    on delete set null;
