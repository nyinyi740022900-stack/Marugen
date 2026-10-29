set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
do $$ begin
 update public.settings set shop_name='Staff may edit ordinary settings';
 insert into public.settings(id, shop_name) values(1, 'Ordinary settings upsert')
 on conflict(id) do update set shop_name=excluded.shop_name;
 begin
  update public.settings set support_contacts='[{"id":"s","name":"Staff","category":"Orders","phone":"+6588889999"}]';
  raise exception 'Staff changed support directory';
 exception when insufficient_privilege then null;
 end;
 begin
  insert into public.settings(id) values (2);
  raise exception 'Staff inserted settings bypass';
 exception when insufficient_privilege then null;
 end;
 begin
  delete from public.settings where id=1;
  raise exception 'Staff deleted directory';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
do $$ begin
 update public.settings set support_contacts='[{"id":"owner-contact","name":"Mei","category":"Orders","phone":"+6588889999"}]';
 if jsonb_array_length((select support_contacts from public.settings where id=1)) <> 1 then raise exception 'Owner save failed'; end if;
 begin
  update public.settings set support_contacts='[{"id":"bad","name":"Mei","category":"Orders","phone":"88889999"}]';
  raise exception 'Invalid phone accepted';
 exception when check_violation then null;
 end;
 begin
  update public.settings set support_contacts='[{"id":"bad","name":"Mei","category":"Orders","email":"a@example.com?bcc=other@example.com"}]';
  raise exception 'Unsafe email accepted';
 exception when check_violation then null;
 end;
 begin
  update public.settings set support_contacts='[{"id":"bad","name":"Mei","category":"Orders"}]';
  raise exception 'No channels accepted';
 exception when check_violation then null;
 end;
 begin
  update public.settings set support_contacts='[{"id":"a","name":"Mei","category":"Orders","phone":"+6588889999"},{"id":"a","name":"Mei","category":"Orders","phone":"+6588889999"}]';
  raise exception 'Duplicate IDs accepted';
 exception when check_violation then null;
 end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
do $$ begin
 insert into public.settings(id, shop_name) values(1, 'Staff ordinary upsert with directory')
 on conflict(id) do update set shop_name=excluded.shop_name;
 if jsonb_array_length((select support_contacts from public.settings where id=1)) <> 1 then raise exception 'Staff upsert lost support directory'; end if;
 begin
  update public.settings set support_contacts='[]';
  raise exception 'Staff cleared support directory';
 exception when insufficient_privilege then null;
 end;
 begin
  update public.settings set id=9 where id=1;
  raise exception 'Staff moved directory row';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claim.sub', '', false);
do $$ begin
 begin
  update public.settings set support_contacts='[]';
  raise exception 'Missing subject bypassed owner check';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
set role service_role;
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claim.role', 'service_role', false);
update public.settings set support_contacts='[]';
reset role;
select 'Support owner boundary and validation passed' as result;
