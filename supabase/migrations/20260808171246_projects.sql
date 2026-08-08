-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: projects
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Reusable updated_at trigger function
-- projects is the first table with an updated_at column that needs to
-- auto-update on row change. Written as a shared function since invoices,
-- proposals, and documents will likely want the same behavior later —
-- one function, attached per-table below.
-- ----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. projects
-- ----------------------------------------------------------------------------
create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  title text not null,
  description text,
  status text not null default 'draft' check (status in (
    'draft', 'active', 'on_hold', 'completed', 'archived'
  )),
  client_id uuid references profiles(id),
  address text,
  start_date date,
  end_date date,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column projects.client_id is 'The client assigned to this project. Nullable — a project may exist before a client is attached.';
comment on column projects.address is 'Job site address.';

create trigger set_projects_updated_at
  before update on projects
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 3. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_projects_organization_id on projects (organization_id);
create index if not exists idx_projects_client_id on projects (client_id);
create index if not exists idx_projects_status on projects (status);

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (Section 7.2)
-- Owner/Pro: full CRUD on own org.
-- Client: read only, own assigned projects (client_id = self).
-- Driver: no direct read via this table per 7.2 — drivers see projects
-- through project_assignments instead, built in the next migration.
-- ----------------------------------------------------------------------------
alter table projects enable row level security;

create policy "projects_owner_pro_full_access"
  on projects for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

create policy "projects_client_read_own"
  on projects for select
  to authenticated
  using (
    client_id = auth.uid()
  );

create policy "admin_bypass_projects"
  on projects for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ============================================================================
-- End of migration
-- ============================================================================
