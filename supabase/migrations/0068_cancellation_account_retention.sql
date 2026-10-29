-- Match existing retained-order behavior (0051): removing an account must not
-- delete its financial decisions or make customer account deletion fail.
begin;
alter table public.order_cancellation_requests alter column user_id drop not null;
alter table public.order_cancellation_requests drop constraint order_cancellation_requests_user_id_fkey;
alter table public.order_cancellation_requests add constraint order_cancellation_requests_user_id_fkey
 foreign key(user_id) references public.profiles(id) on delete set null;
alter table public.order_cancellation_requests drop constraint order_cancellation_requests_reviewed_by_fkey;
alter table public.order_cancellation_requests add constraint order_cancellation_requests_reviewed_by_fkey
 foreign key(reviewed_by) references public.profiles(id) on delete set null;
-- The review timestamp retains a decided state after its reviewer is removed.
alter table public.order_cancellation_requests drop constraint order_cancellation_requests_check;
alter table public.order_cancellation_requests add constraint order_cancellation_requests_check check (
 (status='requested' and reviewed_at is null and reviewed_by is null)
 or (status in('approved','rejected') and reviewed_at is not null)
);
commit;
