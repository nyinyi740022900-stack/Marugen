-- Disposable database only. Runs BEFORE migration 0077: one order cancelled
-- and one refunded under the old trigger, to check what 0077 does with
-- history. Values are synthetic.
\set ON_ERROR_STOP on
insert into auth.users (id, email) values
  ('77000000-0000-0000-0000-0000000000f1', 'old-buyer@example.invalid');
insert into public.products (id, name, category, price, stock_quantity) values
  ('77100000-0000-0000-0000-0000000000f1', 'Old filter pad', 'accessories', 5, 5);

-- Cancelled before 0077: the old trigger returned its 2 units (5 -> 3 -> 5).
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-0000000000f1', '77000000-0000-0000-0000-0000000000f1', 'pending', 10);
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('77200000-0000-0000-0000-0000000000f1', '77100000-0000-0000-0000-0000000000f1', 'Old filter pad', 2, 5);
update public.orders set status = 'cancelled' where id = '77200000-0000-0000-0000-0000000000f1';

-- Refunded before 0077: the old trigger kept its 1 unit (5 -> 4).
insert into public.orders (id, user_id, status, total) values
  ('77200000-0000-0000-0000-0000000000f2', '77000000-0000-0000-0000-0000000000f1', 'pending', 5);
insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values
  ('77200000-0000-0000-0000-0000000000f2', '77100000-0000-0000-0000-0000000000f1', 'Old filter pad', 1, 5);
update public.orders set status = 'paid', stripe_payment_intent_id = 'pi_old_refunded'
 where id = '77200000-0000-0000-0000-0000000000f2';
update public.orders set status = 'refunded' where id = '77200000-0000-0000-0000-0000000000f2';

do $$ begin
  if (select stock_quantity from public.products
       where id = '77100000-0000-0000-0000-0000000000f1') <> 4 then
    raise exception 'Fixture: pre-0077 baseline changed (expected the refund gap, stock 4)';
  end if;
end $$;
