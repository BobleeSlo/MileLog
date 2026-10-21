-- Free and paid plans: entitlements, the public allowance setting, anonymous usage
-- counters and closed months. Built on the 20261001000000 baseline.

-- Entitlements ---------------------------------------------------------------
-- Written only by Edge Functions with the secret key (verify-purchase,
-- apple-notifications) and by tools/grant_entitlement.py. Clients read their own rows.

create table if not exists public.entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null check (source in ('apple', 'complimentary')),
  original_transaction_id text unique,
  product_id text,
  status text not null check (status in ('active', 'grace', 'billing_retry', 'expired', 'revoked')),
  expires_at timestamptz,
  environment text check (environment in ('Production', 'Sandbox', 'Xcode', 'LocalTesting')),
  -- signedDate of the newest Apple payload applied; older payloads are ignored.
  last_signed_at timestamptz,
  -- Names a complimentary grant (e.g. 'beta-2026', 'tester-year'); one row per user and tag.
  grant_tag text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (source <> 'apple' or original_transaction_id is not null),
  check (source <> 'complimentary' or grant_tag is not null)
);

create unique index if not exists entitlements_user_grant_tag
  on public.entitlements (user_id, grant_tag) where grant_tag is not null;
create index if not exists entitlements_user_id on public.entitlements (user_id);

drop trigger if exists entitlements_touch on public.entitlements;
create trigger entitlements_touch before update on public.entitlements
  for each row execute function public.touch_updated_at();

alter table public.entitlements enable row level security;
drop policy if exists own_entitlements on public.entitlements;
create policy own_entitlements on public.entitlements for select to authenticated
  using (auth.uid() = user_id);
revoke insert, update, delete, truncate on public.entitlements from anon, authenticated;

-- App Store Server Notification deduplication (service role only).

create table if not exists public.apple_notifications_seen (
  notification_uuid uuid primary key,
  received_at timestamptz not null default now()
);
alter table public.apple_notifications_seen enable row level security;
revoke all on public.apple_notifications_seen from anon, authenticated;

-- Public configuration -------------------------------------------------------

create table if not exists public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_config enable row level security;
drop policy if exists read_app_config on public.app_config;
create policy read_app_config on public.app_config for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.app_config from anon, authenticated;

insert into public.app_config (key, value) values ('free_auto_trips_per_month', '15')
  on conflict (key) do nothing;

-- Anonymous usage counters ---------------------------------------------------
-- No user, device or location: one row per month, metric and bucket counting how many
-- accounts reported that bucket. Clients can't touch the table; they call record_usage.

create table if not exists public.usage_counters (
  month date not null,
  metric text not null,
  bucket text not null,
  count integer not null default 0,
  primary key (month, metric, bucket)
);
alter table public.usage_counters enable row level security;
revoke all on public.usage_counters from anon, authenticated;

create or replace function public.record_usage(p_month date, p_metric text, p_bucket text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  this_month date := date_trunc('month', now() at time zone 'utc')::date;
begin
  if p_metric not in ('auto_trips', 'report_generations', 'receipt_saves', 'month_end_check_opens') then
    raise exception 'unknown metric' using errcode = '22023';
  end if;
  if p_bucket not in ('0', '1-5', '6-10', '11-15', '16-25', '26-50', '51-100', '101+') then
    raise exception 'unknown bucket' using errcode = '22023';
  end if;
  if p_month is null or p_month not in (this_month, (this_month - interval '1 month')::date) then
    raise exception 'month out of range' using errcode = '22023';
  end if;
  insert into public.usage_counters (month, metric, bucket, count)
    values (p_month, p_metric, p_bucket, 1)
    on conflict (month, metric, bucket) do update set count = public.usage_counters.count + 1;
end;
$$;

revoke execute on function public.record_usage(date, text, text) from public, anon;
grant execute on function public.record_usage(date, text, text) to authenticated;

-- Closed months --------------------------------------------------------------
-- Generating a month's report after it ends closes it for the vehicles it covers;
-- trips in a closed month lock. Insert-only for the owner.

create table if not exists public.closed_months (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  report_kind text not null check (report_kind in ('own_car', 'company_logbook')),
  closed_at timestamptz not null default now(),
  unique (user_id, vehicle_id, month)
);
alter table public.closed_months enable row level security;
drop policy if exists read_own_closed_months on public.closed_months;
create policy read_own_closed_months on public.closed_months for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists insert_own_closed_months on public.closed_months;
create policy insert_own_closed_months on public.closed_months for insert to authenticated
  with check (auth.uid() = user_id
              and exists (select 1 from public.vehicles v where v.id = vehicle_id and v.user_id = auth.uid()));
revoke update, delete, truncate on public.closed_months from anon, authenticated;

-- Audit log ------------------------------------------------------------------
-- The baseline only lets owners read trip_audit_log, so the app's queued audit
-- entries were refused (the table is empty on the live project). Owners may now
-- insert their own entries; there is still no update or delete.
-- user_id gains the auth.users cascade every other per-user table has; trip_id stays
-- without a foreign key so deleting a trip never erases its audit trail.

drop policy if exists insert_own_audit on public.trip_audit_log;
create policy insert_own_audit on public.trip_audit_log for insert to authenticated
  with check (auth.uid() = user_id);
revoke update, delete, truncate on public.trip_audit_log from anon, authenticated;

do $$ begin
  alter table public.trip_audit_log
    add constraint trip_audit_log_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade;
exception when duplicate_object then null; end $$;
