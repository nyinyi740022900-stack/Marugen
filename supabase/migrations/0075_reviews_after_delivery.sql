-- Reviews only after delivery (whole-app audit U1).
--
-- Any paid order used to qualify, so a customer could review a fish that
-- had not arrived yet, or one from an order that was later refunded.
-- Existing reviews are left as they are; customers can still edit theirs.
drop policy if exists "Verified buyers can insert their own reviews"
  on public.product_reviews;
create policy "Verified buyers can insert their own reviews"
  on public.product_reviews for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.order_items oi
      join public.orders o on o.id = oi.order_id
      where oi.product_id = product_reviews.product_id
        and o.user_id = auth.uid()
        and o.status = 'delivered'
    )
  );
