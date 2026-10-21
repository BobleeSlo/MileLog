-- Columns the iOS app has been sending that the database never got.
--
-- PostgREST rejects a whole insert/upsert with HTTP 400 when it names a
-- column the table doesn't have. The app leaves a field out of the request
-- while it's empty, so these saves only started failing once a value was
-- set: settings (energy_mode is always set) have not synced since
-- 2026-07-27, classified trips (reviewed_at) and vehicles with potni nalog
-- details (seat_count, vehicle_type_description) were rejected too.
--
-- All additive and nullable: existing rows and older app builds are
-- unaffected.

alter table public.trips
  add column if not exists reviewed_at timestamptz;

alter table public.vehicles
  add column if not exists seat_count integer,
  add column if not exists vehicle_type_description text;

alter table public.user_settings
  add column if not exists energy_mode text,
  add column if not exists company_name text,
  add column if not exists company_address text,
  add column if not exists company_location text,
  add column if not exists driver_name text,
  add column if not exists trip_beneficiary text,
  add column if not exists trip_area text;
