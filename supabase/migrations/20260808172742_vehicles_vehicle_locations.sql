-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: vehicles, vehicle_locations
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2/7.3 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. vehicles (fleet module)
-- ----------------------------------------------------------------------------
create table if not exists vehicles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  name text not null,
  license_plate text,
  assigned_driver_id uuid references profiles(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table vehicles is 'A fleet vehicle belonging to an organization. Section 5.1, fleet module.';
comment on column vehicles.name is 'e.g. Truck 1, Van - John.';
comment on column vehicles.assigned_driver_id is 'Currently assigned driver, if any. Nullable — a vehicle can exist unassigned.';

-- No Section 6 index entry exists for vehicles (unlike every other table,
-- which gets its FK/filter columns explicitly listed). Following the same
-- discipline as project_assignments/proposals/etc — index exactly what
-- Section 6 lists, nothing more — so no index is added here. Flagging this
-- as a gap rather than guessing: organization_id is hit on every RLS check
-- for this table same as everywhere else, so this may be an oversight in
-- the doc worth a deliberate call rather than a silent index addition.

-- ----------------------------------------------------------------------------
-- 2. Row Level Security — vehicles (Section 7.2)
-- Owner/Pro: full CRUD on own org. Client/Driver: no access.
-- ----------------------------------------------------------------------------
alter table vehicles enable row level security;

create policy "vehicles_owner_pro_full_access"
  on vehicles for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

create policy "admin_bypass_vehicles"
  on vehicles for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ----------------------------------------------------------------------------
-- 3. vehicle_locations (fleet module)
-- Append-only. Driver app inserts a row roughly every 30 seconds while a
-- job is active (Section 9.4). Dashboard reads latest-per-vehicle and
-- subscribes via Supabase Realtime (Section 4.2, Section 8.5). No update or
-- delete path for anyone but platform_admin — rows are never mutated.
-- ----------------------------------------------------------------------------
create table if not exists vehicle_locations (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references vehicles(id),
  organization_id uuid not null references organizations(id),
  driver_id uuid not null references profiles(id),
  latitude double precision not null,
  longitude double precision not null,
  accuracy_meters real,
  recorded_at timestamptz not null default now()
);

comment on table vehicle_locations is 'Append-only GPS pings from the driver app. Section 5.1, fleet module. Latest row per vehicle drives the live fleet map.';
comment on column vehicle_locations.accuracy_meters is 'GPS accuracy reading, if the device reports one.';

-- ----------------------------------------------------------------------------
-- 4. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_vehicle_locations_vehicle_recorded
  on vehicle_locations (vehicle_id, recorded_at desc);

-- ----------------------------------------------------------------------------
-- 5. Row Level Security — vehicle_locations (Section 7.2 + 7.3)
-- Owner/Pro: read all in own org. Driver: insert only for own driver_id.
-- Client: no access. Module-gated per Section 7.3 — has_active_module()
-- is ANDed directly into each policy's condition rather than added as its
-- own permissive policy, since separate permissive policies on the same
-- command are OR'd together in Postgres RLS and a standalone gating policy
-- would let any other matching policy bypass it entirely.
-- ----------------------------------------------------------------------------
alter table vehicle_locations enable row level security;

create policy "vehicle_locations_owner_pro_read"
  on vehicle_locations for select
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
    and has_active_module('fleet_tracking')
  );

create policy "vehicle_locations_driver_insert_own"
  on vehicle_locations for insert
  to authenticated
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and driver_id = auth.uid()
    and has_active_module('fleet_tracking')
  );

create policy "admin_bypass_vehicle_locations"
  on vehicle_locations for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ============================================================================
-- End of migration
-- ============================================================================
