-- Optional customer instructions, stored separately from the delivery address.
-- Existing orders remain valid and retain NULL. Existing order SELECT policies
-- restrict visibility to the customer who owns the order and authorized admins.
alter table public.orders
  add column customer_remarks text
  constraint orders_customer_remarks_length_check
  check (customer_remarks is null or char_length(customer_remarks) <= 500);

comment on column public.orders.customer_remarks is
  'Optional customer requests entered at checkout; plain text, up to 500 Unicode characters.';

-- Monotonic checkout revisions prevent delayed payment retries from replacing
-- the customer's latest instructions. Existing clients use revision zero.
alter table public.orders
  add column customer_remarks_revision integer not null default 0
  constraint orders_customer_remarks_revision_check
  check (customer_remarks_revision >= 0);
