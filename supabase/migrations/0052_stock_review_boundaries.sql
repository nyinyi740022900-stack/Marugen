-- Orders are created only by the service backend. Customer pending-order
-- inserts still reserve real stock, even when no payment is ever made.
drop policy if exists "Users can create their own orders" on public.orders;
drop policy if exists "Users can create their own pending orders" on public.orders;
drop policy if exists "Users can insert items into their own orders" on public.order_items;
drop policy if exists "Users can insert items into their own pending orders" on public.order_items;

-- Historical invalid quantities are preserved for explicit investigation.
-- NOT VALID skips the historical scan but rejects every new/updated row.
-- After auditing old rows, validate this constraint in a separate migration.
alter table public.order_items add constraint order_items_positive_quantity
  check (quantity > 0) not valid;

-- Validate before the existing AFTER INSERT stock trigger can mutate stock.
-- Keep atomic conditional decrements in apply_order_item_stock (0020).
create or replace function public.validate_order_item_stock_input()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_order_status text;
  v_category text;
  v_sizes text[];
  v_has_size_stocks boolean;
begin
  -- Serialize item insertion with cancellation. The parent lock is held
  -- through the AFTER INSERT stock mutation and transaction commit. If
  -- cancellation wins first, its committed terminal status rejects the
  -- late reservation; if insertion wins, cancellation sees/restores it.
  select status into v_order_status from public.orders
   where id = new.order_id for update;
  if not found or v_order_status <> 'pending' then
    raise exception 'Stock may only be reserved for a pending order';
  end if;

  if new.quantity is null or new.quantity <= 0 then
    raise exception 'Order item quantity must be positive' using errcode = '23514';
  end if;

  -- Detached historical snapshots have no stock to apply. A variant cannot
  -- be detached independently from its product because cancel uses both.
  if new.product_id is null then
    if new.variant_id is not null or new.size_label is not null then
      raise exception 'Order item variant/size requires a product' using errcode = '23514';
    end if;
    return new;
  end if;

  select category, size_options into v_category, v_sizes
    from public.products where id = new.product_id;
  if not found then
    raise exception 'Order item product does not exist: %', new.product_id using errcode = '23514';
  end if;

  if v_category in ('koi', 'arowana') and new.quantity <> 1 then
    raise exception 'Live fish quantity must be 1' using errcode = '23514';
  end if;

  if new.variant_id is not null then
    if not exists (select 1 from public.product_variants
                    where id = new.variant_id and product_id = new.product_id) then
      raise exception 'Order item variant does not belong to product' using errcode = '23514';
    end if;
  elsif exists (select 1 from public.product_variants where product_id = new.product_id) then
    raise exception 'Order item product requires a variant' using errcode = '23514';
  end if;

  if v_category not in ('koi', 'arowana') and cardinality(v_sizes) > 0 then
    if new.size_label is null or btrim(new.size_label) = ''
       or not (new.size_label = any(v_sizes)) then
      raise exception 'Order item requires a valid product size' using errcode = '23514';
    end if;
  elsif new.size_label is not null then
    raise exception 'Order item product does not accept a size' using errcode = '23514';
  end if;

  if new.variant_id is not null then
    select exists (select 1 from public.product_variant_size_stocks
                    where variant_id = new.variant_id) into v_has_size_stocks;
    -- Do not fall back to weight stock if a product requires size selection
    -- but its inventory matrix is missing or incomplete.
    if new.size_label is not null or v_has_size_stocks then
      if new.size_label is null or not exists (
        select 1 from public.product_variant_size_stocks
         where variant_id = new.variant_id and size_label = new.size_label
      ) then
        raise exception 'Order item requires a valid variant size stock cell' using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger order_items_validate_stock_input
  before insert on public.order_items
  for each row execute function public.validate_order_item_stock_input();

-- RLS decides which review a customer owns, but cannot compare OLD fields.
-- Preserve shop moderation/replies while allowing ordinary rating/comment
-- edits. INVOKER is intentional: current_user must be the calling DB role,
-- not the function owner (as it would be inside a SECURITY DEFINER).
-- Neither a missing subject nor a client-editable JWT field grants bypass.
create or replace function public.protect_review_admin_fields()
returns trigger
language plpgsql
security invoker set search_path = public
as $$
begin
  if current_user not in ('service_role', 'postgres', 'supabase_admin')
     and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.is_hidden := false;
      new.admin_reply := null;
      new.admin_reply_at := null;
    else
      new.is_hidden := old.is_hidden;
      new.admin_reply := old.admin_reply;
      new.admin_reply_at := old.admin_reply_at;
    end if;
  end if;
  return new;
end;
$$;

create trigger product_reviews_protect_admin_fields
  before insert or update on public.product_reviews
  for each row execute function public.protect_review_admin_fields();
