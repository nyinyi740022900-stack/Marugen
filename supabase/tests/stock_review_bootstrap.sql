-- Local PostgreSQL only: minimal Supabase auth/storage primitives plus the
-- actual migrations that define the boundaries exercised by this suite.
\set ON_ERROR_STOP on
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema storage;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.role', true), '');
$$;
create table storage.buckets (id text primary key, name text, public boolean);
create table storage.objects (id uuid, bucket_id text);
\ir ../migrations/0001_init.sql
\ir ../migrations/0005_reviews.sql
\ir ../migrations/0006_promo_codes.sql
\ir ../migrations/0007_customer_order_cancel.sql
\ir ../migrations/0008_product_variants.sql
\ir ../migrations/0009_verified_reviews.sql
\ir ../migrations/0010_payment_integrity.sql
\ir ../migrations/0011_review_moderation.sql
\ir ../migrations/0019_product_size_options.sql
\ir ../migrations/0020_variant_size_stocks.sql
\ir ../migrations/0026_lock_down_order_inserts.sql
\ir ../migrations/0030_order_status_forward_only.sql
\ir ../migrations/0031_review_shop_reply.sql
\ir ../migrations/0036_prevent_role_escalation.sql
\ir ../migrations/0037_lock_review_reassignment.sql
\ir ../migrations/0041_payment_intent_idempotency.sql
\ir ../migrations/0048_order_refund_tracking.sql
grant usage on schema auth, public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
