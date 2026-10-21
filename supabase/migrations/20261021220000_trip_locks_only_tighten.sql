-- Locks only tighten (KTD10), enforced in the database too: an update that would
-- unlock a locked trip keeps it locked instead of raising, so a device pushing a
-- stale unlocked copy can never reopen a closed month and never gets stuck
-- retrying. Same body as the baseline trip_lock_guard plus the first block.

create or replace function public.trip_lock_guard() returns trigger language plpgsql as $$
begin
  if old.is_locked and not coalesce(new.is_locked, false) then
    new.is_locked = true;
    new.locked_at = old.locked_at;
  end if;
  if old.is_locked then
    if new.started_at is distinct from old.started_at
       or new.odometer_start_km is distinct from old.odometer_start_km
       or new.odometer_end_km is distinct from old.odometer_end_km
       or new.distance_km is distinct from old.distance_km
       or new.vehicle_id is distinct from old.vehicle_id then
      raise exception 'Trip is locked; mileage/date/vehicle cannot be changed';
    end if;
  end if;
  return new;
end; $$;
