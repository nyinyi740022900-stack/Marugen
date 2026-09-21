-- Security hardening: "Users can update their own reviews" (0005_reviews.sql)
-- only pins auth.uid() = user_id, not which columns can change — a customer
-- could repoint their own review's product_id (or user_id) to a different
-- product after the fact, corrupting that product's rating aggregate with
-- a review that was never actually written for it. RLS's WITH CHECK can't
-- reference the row's OLD values, so this is enforced with a trigger
-- instead (same pattern as prevent_role_self_escalation in 0036).
create or replace function public.prevent_review_reassignment()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    new.product_id := old.product_id;
    new.user_id := old.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_review_reassignment on public.product_reviews;
create trigger trg_prevent_review_reassignment
  before update on public.product_reviews
  for each row execute function public.prevent_review_reassignment();
