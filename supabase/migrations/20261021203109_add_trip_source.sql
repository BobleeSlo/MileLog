-- How each trip was started: 'auto' (trip detector) or 'manual' (Record screen).
-- The free plan's monthly allowance counts automatic trips, so the value is set once
-- and never changes afterwards.
--
-- Nullable while builds without the field still sync. When such a build inserts a
-- trip, the trigger fills the value with the rule the app uses for old trips: the
-- notes contain the literal "Auto-detected". Once set, an update can't change it —
-- the trigger keeps the stored value rather than raising, so a client that disagrees
-- never gets stuck retrying a push.
--
-- The baseline lock guard (trip_lock_guard) only blocks started_at, odometer, distance
-- and vehicle on locked rows, so setting source on a locked trip already passes it.

alter table public.trips add column if not exists source text;

do $$ begin
  alter table public.trips add constraint trips_source_check check (source in ('auto', 'manual'));
exception when duplicate_object then null; end $$;

create or replace function public.trip_source_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and old.source is not null then
    new.source = old.source;
  elsif new.source is null then
    new.source = case when position('Auto-detected' in coalesce(new.notes, '')) > 0
                      then 'auto' else 'manual' end;
  end if;
  return new;
end; $$;

drop trigger if exists trips_source on public.trips;
create trigger trips_source before insert or update on public.trips
  for each row execute function public.trip_source_guard();

-- Backfill existing rows with the same rule; safe to re-run. updated_at is left alone.
alter table public.trips disable trigger trips_touch;
update public.trips
   set source = case when position('Auto-detected' in coalesce(notes, '')) > 0 then 'auto' else 'manual' end
 where source is null;
alter table public.trips enable trigger trips_touch;
