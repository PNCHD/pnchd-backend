-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: organizations + profiles
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. organizations
-- ----------------------------------------------------------------------------
create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid references auth.users(id),
  seat_count integer not null default 1,
  stripe_customer_id text,
  stripe_connect_account_id text,
  stripe_connect_onboarded boolean not null default false,
  founding_member boolean not null default false,
  founding_member_price_cents integer,
  founding_member_modules_locked_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table organizations is 'A contractor''s business. All platform data is scoped to an organization.';
comment on column organizations.founding_member_price_cents is 'Locked price promised to this org (e.g. 3900 = $39.00). Stored explicitly so the commitment is auditable independent of Stripe config.';
comment on column organizations.founding_member_modules_locked_at is 'Timestamp when founding member signed up. Modules added within 12 months of this date are included free.';

-- ----------------------------------------------------------------------------
-- 2. profiles
-- Extends auth.users. Created automatically via trigger below.
-- ----------------------------------------------------------------------------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid references organizations(id),
  role text not null check (role in ('owner', 'pro', 'client', 'driver', 'platform_admin')),
  full_name text,
  avatar_url text,
  phone text,
  push_token text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table profiles is 'Extends auth.users. organization_id is NULL until the signup flow attaches the profile to a newly created org.';

-- ----------------------------------------------------------------------------
-- 3. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_profiles_organization_id on profiles (organization_id);
create index if not exists idx_profiles_role on profiles (role);

-- ----------------------------------------------------------------------------
-- 4. Auto-create profile trigger
--
-- Fires on every new auth.users row. organization_id is left NULL here —
-- your signup flow (React /signup route or Edge Function) must update this
-- profile with the real organization_id immediately after it creates the
-- organizations row for a new owner. Default role is 'owner' because the
-- only path that inserts directly into auth.users is your own signup flow;
-- clients/drivers are provisioned via invite (see Section 8.4/notifications
-- work later — invite flow should set role explicitly, not rely on this
-- default).
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    coalesce(new.raw_user_meta_data ->> 'role', 'owner')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ----------------------------------------------------------------------------
-- 5. Row Level Security
-- ----------------------------------------------------------------------------
alter table organizations enable row level security;
alter table profiles enable row level security;

-- organizations: owner/pro full CRUD on their own org.
-- Uses owner_id directly here (not the standard org_isolation pattern from
-- 7.1) since organizations IS the org row, not a child table — matching it
-- against profiles.organization_id would work too, but owner_id is more
-- direct and avoids a self-referential subquery.
create policy "org_members_can_read_own_org"
  on organizations for select
  using (
    id = (select organization_id from profiles where id = auth.uid())
  );

create policy "org_owner_can_update_own_org"
  on organizations for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "org_owner_can_insert_own_org"
  on organizations for insert
  with check (owner_id = auth.uid());

-- platform_admin bypass (Section 15.3 — added now so it's not forgotten later)
create policy "admin_bypass_organizations"
  on organizations for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- profiles: read all within own org, update own row only (Section 7.2)
create policy "profiles_read_within_org"
  on profiles for select
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    or id = auth.uid()
  );

create policy "profiles_update_own_row"
  on profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "admin_bypass_profiles"
  on profiles for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ============================================================================
-- End of migration
-- ============================================================================
