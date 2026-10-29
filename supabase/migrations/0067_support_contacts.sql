-- Public contact details only. No account creation or role grants.
alter table public.settings
  add column if not exists support_contacts jsonb not null default '[]'::jsonb;

create or replace function public.valid_support_contacts(directory jsonb)
returns boolean language plpgsql immutable set search_path = public, pg_temp
as $$
declare contact jsonb; channel text; value text; ids text[] := '{}'; has_channel boolean;
begin
  if directory is null or jsonb_typeof(directory) <> 'array' then return false; end if;
  if jsonb_array_length(directory) > 30 then return false; end if;
  for contact in select jsonb_array_elements(directory) loop
    if jsonb_typeof(contact) <> 'object' then return false; end if;
    if jsonb_typeof(contact->'id') is distinct from 'string'
       or jsonb_typeof(contact->'name') is distinct from 'string'
       or jsonb_typeof(contact->'category') is distinct from 'string' then return false; end if;
    if length(contact->>'id') not between 1 and 64
       or (contact->>'id') !~ '^[A-Za-z0-9_-]+$'
       or (contact->>'id') = any(ids) then return false; end if;
    ids := array_append(ids, contact->>'id');
    if length(btrim(contact->>'name')) not between 1 and 80
       or length(btrim(contact->>'category')) not between 1 and 120
       or (contact->>'name') ~ '[[:cntrl:]]'
       or (contact->>'category') ~ '[[:cntrl:]]' then return false; end if;
    has_channel := false;
    foreach channel in array array['whatsapp','phone','email'] loop
      if contact->channel is null or contact->channel = 'null'::jsonb then continue; end if;
      if jsonb_typeof(contact->channel) <> 'string' then return false; end if;
      value := contact->>channel;
      if value ~ '[[:cntrl:]]' then return false; end if;
      value := btrim(value);
      if value = '' then continue; end if;
      has_channel := true;
      if channel in ('whatsapp', 'phone') and value !~ '^\+[1-9][0-9]{6,14}$' then return false; end if;
      if channel = 'email' and (length(value) > 254 or
        value !~ '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+$') then return false; end if;
    end loop;
    if not has_channel then return false; end if;
  end loop;
  return true;
end $$;

alter table public.settings add constraint settings_support_contacts_valid
  check (public.valid_support_contacts(support_contacts));

-- The existing settings policy permits staff writes. Restrict this field
-- independently, including INSERT/DELETE or moving the single-row key.
create or replace function public.guard_support_contacts_owner()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare protected_change boolean;
begin
  if tg_op = 'UPDATE' then
    protected_change := new.support_contacts is distinct from old.support_contacts
      or new.id is distinct from old.id;
  elsif tg_op = 'INSERT' then
    -- PostgREST upserts run BEFORE INSERT even when they only update
    -- ordinary columns on the existing row. Let that reach UPDATE,
    -- where a changed directory is checked against the actual old value.
    protected_change := new.support_contacts <> '[]'::jsonb
      or not exists(select 1 from public.settings where id = new.id);
  else
    protected_change := true;
  end if;
  if protected_change then
    if coalesce(auth.role(), '') <> 'service_role'
      and not (auth.uid() is null and session_user in ('postgres','supabase_admin')
        and coalesce(current_setting('role', true), 'none') in ('none','postgres','supabase_admin'))
      and not exists(select 1 from public.profiles where id = auth.uid() and role = 'owner') then
      raise exception 'Only the owner can manage support contacts' using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
revoke all on function public.guard_support_contacts_owner() from public;
create trigger settings_support_contacts_owner
  before insert or update or delete on public.settings
  for each row execute function public.guard_support_contacts_owner();
