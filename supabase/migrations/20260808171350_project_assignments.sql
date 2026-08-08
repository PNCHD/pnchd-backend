-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: project_assignments
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. project_assignments
-- Links drivers/field staff to projects. Multiple drivers may be assigned
-- to one project.
-- ----------------------------------------------------------------------------
create table if not exists project_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id),
  profile_id uuid not null references profiles(id),
  organization_id uuid not null references organizations(id),
  assigned_at timestamptz not null default now(),
  is_active boolean not null default true
);

comment on column project_assignments.profile_id is 'The assigned driver/employee.';

-- ----------------------------------------------------------------------------
-- 2. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_project_assignments_project_id on project_assignments (project_id);
create index if not exists idx_project_assignments_profile_id on project_assignments (profile_id);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security (Section 7.2)
-- Owner/Pro: full CRUD on own org.
-- Client/Driver: read own assignments only (profile_id = self).
-- ----------------------------------------------------------------------------
alter table project_assignments enable row level security;

create policy "project_assignments_owner_pro_full_access"
  on project_assignments for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

create policy "project_assignments_driver_read_own"
  on project_assignments for select
  to authenticated
  using (
    profile_id = auth.uid()
  );

create policy "admin_bypass_project_assignments"
  on project_assignments for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ----------------------------------------------------------------------------
-- 4. Driver read access on projects (completes the policy set from
-- migration 003). A driver can read a project only if they have an active
-- assignment to it — this is the piece that migration 003 was missing.
-- ----------------------------------------------------------------------------
create policy "projects_driver_read_assigned"
  on projects for select
  to authenticated
  using (
    exists (
      select 1 from project_assignments
      where project_assignments.project_id = projects.id
      and project_assignments.profile_id = auth.uid()
      and project_assignments.is_active = true
    )
  );

-- ============================================================================
-- End of migration
-- ============================================================================
