-- Baseline: the public schema as it ran live on 2026-10-21 (project rjkohvddlenyeywhxulc),
-- before 20261019200545_add_missing_app_columns. Exported from the live catalog so that
-- later migrations have something to build on. The live project already has all of this;
-- it is never re-applied there (mark it applied: `supabase migration repair --status applied 20261001000000`).
--
-- What the lock trigger allows: on a row with is_locked = true, trip_lock_guard rejects a change
-- to started_at, odometer_start_km, odometer_end_km, distance_km or vehicle_id. Every other column
-- (purpose, notes, customer, addresses, ended_at, reviewed_at, is_locked itself, ...) can still change.
--
-- Foreign keys and delete rules:
--   customers, receipts, trips, user_settings, vehicles .user_id -> auth.users  ON DELETE CASCADE
--   receipts.trip_id, trip_points.trip_id               -> trips                 ON DELETE CASCADE
--   trips.vehicle_id -> vehicles, trips.customer_id -> customers                  NO ACTION
--   trip_audit_log has no foreign key at all (neither trip_id nor user_id), so its rows outlive
--   the trip and the user; account deletion has to remove them explicitly.
--   trip_points has no user_id; it goes with its trip.
--
-- Columns added by 20261019200545 (vehicles.default_trip_type/seat_count/vehicle_type_description,
-- trips.locked_at/reviewed_at, user_settings.lock_after_days/commute_rate/energy_mode/company_* ...)
-- are left out here on purpose.

create extension if not exists pgcrypto;

-- Tables ---------------------------------------------------------------------

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  license_plate text not null,
  vehicle_type text not null check (vehicle_type = any (array['own','company'])),
  default_purpose text default 'business' check (default_purpose = any (array['business','private','commute'])),
  current_odometer_km integer default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  bluetooth_name text default '',
  bluetooth_uid text default ''
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  contact_person text,
  address text,
  city text,
  lat double precision,
  lng double precision,
  notes text,
  created_at timestamptz default now()
);

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id),
  sequential_number integer,
  trip_type text not null default 'business' check (trip_type = any (array['business','private','commute'])),
  customer_id uuid references public.customers(id),
  purpose text,
  contact_met text,
  started_at timestamptz not null,
  ended_at timestamptz,
  start_address text,
  start_lat double precision,
  start_lng double precision,
  end_address text,
  end_lat double precision,
  end_lng double precision,
  intermediate_stops jsonb default '[]'::jsonb,
  odometer_start_km integer,
  odometer_end_km integer,
  distance_km numeric,
  reimbursement_rate_eur numeric default 0.430,
  reimbursement_amount_eur numeric,
  notes text,
  is_locked boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.trip_points (
  id bigserial primary key,
  trip_id uuid not null references public.trips(id) on delete cascade,
  recorded_at timestamptz not null,
  lat double precision not null,
  lng double precision not null,
  speed_kmh real,
  accuracy_m real
);

create table if not exists public.trip_audit_log (
  id bigserial primary key,
  trip_id uuid not null,
  user_id uuid not null,
  changed_at timestamptz default now(),
  field_name text,
  old_value text,
  new_value text
);

create table if not exists public.receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  trip_id uuid references public.trips(id) on delete cascade,
  receipt_type text not null check (receipt_type = any (array['fuel','parking','toll','other'])),
  amount_eur numeric,
  vendor text,
  photo_url text,
  receipt_date date,
  notes text,
  created_at timestamptz default now()
);

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reimbursement_rate numeric default 0.430,
  home_address text default '',
  home_lat double precision,
  home_lng double precision,
  work_address text default '',
  work_lat double precision,
  work_lng double precision,
  auto_detect_enabled boolean default false,
  stationary_timeout_minutes integer default 5,
  updated_at timestamptz default now()
);

-- Functions and triggers -----------------------------------------------------

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

create or replace function public.user_settings_touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create or replace function public.trip_before_insert() returns trigger language plpgsql as $$
begin
  if new.sequential_number is null then
    select coalesce(max(sequential_number),0)+1 into new.sequential_number
      from trips where user_id = new.user_id;
  end if;
  if new.odometer_start_km is not null and new.odometer_end_km is not null then
    new.distance_km = new.odometer_end_km - new.odometer_start_km;
  end if;
  if new.distance_km is not null and new.trip_type = 'business' then
    new.reimbursement_amount_eur = round(new.distance_km * coalesce(new.reimbursement_rate_eur,0.430), 2);
  end if;
  return new;
end; $$;

create or replace function public.trip_after_write() returns trigger language plpgsql as $$
begin
  if new.odometer_end_km is not null then
    update vehicles set current_odometer_km = new.odometer_end_km
      where id = new.vehicle_id and current_odometer_km < new.odometer_end_km;
  end if;
  return new;
end; $$;

create or replace function public.trip_lock_guard() returns trigger language plpgsql as $$
begin
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

drop trigger if exists trips_touch on public.trips;
create trigger trips_touch before update on public.trips for each row execute function public.touch_updated_at();
drop trigger if exists trips_bi on public.trips;
create trigger trips_bi before insert on public.trips for each row execute function public.trip_before_insert();
drop trigger if exists trips_aw on public.trips;
create trigger trips_aw after insert or update on public.trips for each row execute function public.trip_after_write();
drop trigger if exists trips_lock on public.trips;
create trigger trips_lock before update on public.trips for each row execute function public.trip_lock_guard();
drop trigger if exists user_settings_touch on public.user_settings;
create trigger user_settings_touch before update on public.user_settings for each row execute function public.user_settings_touch_updated_at();

-- Row level security ---------------------------------------------------------

alter table public.vehicles enable row level security;
alter table public.customers enable row level security;
alter table public.trips enable row level security;
alter table public.trip_points enable row level security;
alter table public.trip_audit_log enable row level security;
alter table public.receipts enable row level security;
alter table public.user_settings enable row level security;

drop policy if exists own_vehicles on public.vehicles;
create policy own_vehicles on public.vehicles for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_customers on public.customers;
create policy own_customers on public.customers for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_trips on public.trips;
create policy own_trips on public.trips for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_points on public.trip_points;
create policy own_points on public.trip_points for all
  using (exists (select 1 from trips t where t.id = trip_points.trip_id and t.user_id = auth.uid()))
  with check (exists (select 1 from trips t where t.id = trip_points.trip_id and t.user_id = auth.uid()));
drop policy if exists own_audit on public.trip_audit_log;
create policy own_audit on public.trip_audit_log for select using (auth.uid() = user_id);
drop policy if exists own_receipts on public.receipts;
create policy own_receipts on public.receipts for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_settings on public.user_settings;
create policy own_settings on public.user_settings for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Receipts storage -----------------------------------------------------------
-- Private bucket; each user reads and writes only under their own lowercase uid folder.

insert into storage.buckets (id, name, public) values ('receipts', 'receipts', false)
  on conflict (id) do nothing;

drop policy if exists "Users can read own receipts" on storage.objects;
create policy "Users can read own receipts" on storage.objects for select
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users can insert own receipts" on storage.objects;
create policy "Users can insert own receipts" on storage.objects for insert
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users can update own receipts" on storage.objects;
create policy "Users can update own receipts" on storage.objects for update
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users can delete own receipts" on storage.objects;
create policy "Users can delete own receipts" on storage.objects for delete
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
