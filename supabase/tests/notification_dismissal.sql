-- Synthetic fixtures only; invoked by the isolated local runner.
insert into public.profiles(id) values
 ('00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000002');
insert into public.orders(id) values ('00000000-0000-0000-0000-000000000010');
insert into public.notifications(id, user_id, title, body, order_id) values
 ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'Own', 'Own update', '00000000-0000-0000-0000-000000000010'),
 ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000002', 'Other', 'Other update', null);
update public.notifications set dismissed_at = '2026-10-26T00:00:00Z' where user_id = '00000000-0000-0000-0000-000000000002';
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
do $$
declare changed integer;
begin
 if (select count(*) from public.notifications) <> 1 then raise exception 'RLS leaked other inbox'; end if;
 update public.notifications set dismissed_at = '2026-10-26T00:00:00Z' where id = '00000000-0000-0000-0000-000000000102';
 get diagnostics changed = row_count;
 if changed <> 0 then raise exception 'Changed another account'; end if;
 update public.notifications set dismissed_at = '2026-10-26T00:00:00Z' where id = '00000000-0000-0000-0000-000000000101';
 get diagnostics changed = row_count;
 if changed <> 1 then raise exception 'Own dismissal failed'; end if;
 if (select count(*) from public.notifications where dismissed_at is null and not read) <> 0 then raise exception 'Dismissed inbox badge not filtered'; end if;
 update public.notifications set dismissed_at = null where dismissed_at = '2026-10-26T00:00:01Z';
 get diagnostics changed = row_count;
 if changed <> 0 then raise exception 'Stale Undo restored a later batch'; end if;
 update public.notifications set dismissed_at = null where dismissed_at = '2026-10-26T00:00:00Z';
 get diagnostics changed = row_count;
 if changed <> 1 then raise exception 'Own Undo failed'; end if;
 if (select count(*) from public.notifications where dismissed_at is null and not read) <> 1 then raise exception 'Undo lost unread flag'; end if;
 delete from public.notifications;
 get diagnostics changed = row_count;
 if changed <> 0 then raise exception 'Client physically deleted a notification'; end if;
end $$;
reset role;
do $$ begin
 if not exists(select 1 from public.notifications where user_id = '00000000-0000-0000-0000-000000000002' and dismissed_at = '2026-10-26T00:00:00Z') then raise exception 'Undo changed another account'; end if;
 if (select count(*) from public.notifications) <> 2 then raise exception 'Notification history lost'; end if;
 if (select count(*) from public.orders) <> 1 then raise exception 'Order history changed'; end if;
 if exists(select 1 from pg_policies where tablename = 'notifications' and cmd = 'DELETE') then raise exception 'Unexpected DELETE policy'; end if;
end $$;
select 'Notification dismissal RLS and batch Undo passed' as result;
