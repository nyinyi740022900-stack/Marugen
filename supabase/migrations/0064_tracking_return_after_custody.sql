begin;
-- A fresh return is a terminal exception after collection/transit. Keep the
-- custody watermark, but allow its distinct carrier status to be recorded.
create or replace function public.accept_easyparcel_tracking(old_code integer,progress smallint,new_code integer,new_text text,old_observed timestamptz,new_observed timestamptz,old_event timestamptz default null,new_event timestamptz default null) returns boolean language sql immutable as $$
 select coalesce(new_code in(0,2,3,4,5,6,7,8,11)
 and (old_observed is null or new_observed>=old_observed)
 and (old_event is null or new_event>=old_event)
 and (old_code not in(5,6) or new_code=old_code or old_code is null)
 and (progress=0 or (new_code in(0,6,8) or public.easyparcel_tracking_progress(new_code)>=progress))
 and (lower(btrim(coalesce(new_text,''))) not in('waiting payment','expired (unpaid)') or (progress=0 and new_code not in(3,4,5,6,11))),false)
$$;
commit;
