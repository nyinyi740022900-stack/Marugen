-- Disposable database only. Runs BEFORE migration 0078: one order paid
-- under the old schema, to check that 0078 leaves its GST snapshot empty
-- instead of stamping today's rate on it. Values are synthetic.
\set ON_ERROR_STOP on
insert into auth.users (id, email) values
  ('78000000-0000-0000-0000-0000000000f1', 'old-buyer@example.invalid');
insert into public.products (id, name, category, price, stock_quantity) values
  ('78100000-0000-0000-0000-0000000000f1', 'Old pellets', 'fish_food', 109, 5);
insert into public.orders (id, user_id, status, total, stripe_payment_intent_id, created_at) values
  ('78200000-0000-0000-0000-0000000000f1', '78000000-0000-0000-0000-0000000000f1',
   'pending', 109, 'pi_s3_old', now() - interval '30 days');
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('78200000-0000-0000-0000-0000000000f1', '78100000-0000-0000-0000-0000000000f1', 'Old pellets', 1, 109);
update public.orders set status = 'paid' where id = '78200000-0000-0000-0000-0000000000f1';
-- The shop's rate today; the old order must not inherit it.
update public.settings set gst_percent = 9, gst_included_in_price = true where id = 1;
