-- Human-readable, date-based order numbers (e.g. "20092026-0001") instead
-- of a raw UUID prefix. One counter per calendar day (Singapore time),
-- incremented atomically via upsert so concurrent checkouts never collide.

create table if not exists public.order_number_counters (
  day date primary key,
  counter int not null default 0
);

alter table public.orders
  add column if not exists order_number text unique;

create or replace function public.assign_order_number()
returns trigger as $$
declare
  today date := (now() at time zone 'Asia/Singapore')::date;
  seq int;
begin
  insert into public.order_number_counters (day, counter)
  values (today, 1)
  on conflict (day) do update set counter = public.order_number_counters.counter + 1
  returning counter into seq;

  new.order_number := to_char(today, 'DDMMYYYY') || '-' || lpad(seq::text, 4, '0');
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_assign_order_number on public.orders;
create trigger trg_assign_order_number
  before insert on public.orders
  for each row
  when (new.order_number is null)
  execute function public.assign_order_number();

-- Backfill existing orders (in creation order, per calendar day) and seed
-- the counters table so new inserts continue from the right number.
with ordered as (
  select
    id,
    (created_at at time zone 'Asia/Singapore')::date as day,
    row_number() over (
      partition by (created_at at time zone 'Asia/Singapore')::date
      order by created_at
    ) as rn
  from public.orders
  where order_number is null
)
update public.orders o
set order_number = to_char(ordered.day, 'DDMMYYYY') || '-' || lpad(ordered.rn::text, 4, '0')
from ordered
where o.id = ordered.id;

insert into public.order_number_counters (day, counter)
select (created_at at time zone 'Asia/Singapore')::date, count(*)
from public.orders
group by 1
on conflict (day) do update
  set counter = greatest(public.order_number_counters.counter, excluded.counter);
