-- Adds a seller/shop reply to reviews — every major review surface
-- (Amazon, Shopee, Lazada, Google Business reviews) lets the seller post
-- one public reply per review so a bad review isn't left unanswered and a
-- good one can be thanked. One review = one shop here (single-vendor
-- app), so a single reply column is enough — no threading/table needed.
--
-- No RLS change needed: "Admins can moderate reviews" (0011_review_
-- moderation.sql) already grants admins `update` on any column of
-- product_reviews via `public.is_admin()`.

alter table public.product_reviews
  add column if not exists admin_reply text,
  add column if not exists admin_reply_at timestamptz;
