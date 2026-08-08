-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: proposals
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. proposals
-- ----------------------------------------------------------------------------
create table if not exists proposals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  project_id uuid references projects(id),
  client_id uuid not null references profiles(id),
  title text not null,
  status text not null default 'draft' check (status in (
    'draft', 'sent', 'approved', 'rejected', 'expired'
  )),
  subtotal_cents integer not null default 0,
  tax_rate_percent numeric(5,2),
  tax_cents integer,
  total_cents integer not null default 0,
  notes text,
  valid_until date,
  approved_at timestamptz,
  created_at timestamptz not null default now()
);

comment on column proposals.notes is 'Contractor notes visible to client.';
comment on column proposals.subtotal_cents is 'Sum of line items. Money always stored in cents, never floats.';

-- ----------------------------------------------------------------------------
-- 2. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_proposals_org_client
  on proposals (organization_id, client_id);

-- ----------------------------------------------------------------------------
-- 3. Client approval restriction
--
-- Section 7.2 says clients may "write approved_at only." Doing this cleanly
-- needs a trigger, since RLS policies can't restrict which individual
-- columns an UPDATE touches. This trigger:
--   - Blocks a client from changing anything except approved_at
--   - Only allows the change when the proposal is currently 'sent'
--     (can't approve a draft or an already-decided proposal)
--   - Auto-flips status to 'approved' in the same write, so the client
--     app only ever needs to set approved_at, never status directly
--
-- Gap worth flagging: there's no rejected_at column in the doc's schema,
-- so client rejection isn't wired up yet. If you want clients to reject
-- proposals (not just approve), that needs a schema addition — flagging
-- rather than silently adding a column that wasn't specified.
-- ----------------------------------------------------------------------------
create or replace function public.enforce_proposal_client_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_role text;
begin
  select role into current_role from profiles where id = auth.uid();

  if current_role = 'client' then
    if old.status != 'sent' then
      raise exception 'Proposal must be in sent status to be approved';
    end if;

    if new.approved_at is null or old.approved_at is not null then
      raise exception 'Clients may only set approved_at once, on a sent proposal';
    end if;

    -- Confirm nothing else changed except approved_at (and the status
    -- flip this trigger itself performs below).
    if new.organization_id != old.organization_id
      or new.project_id is distinct from old.project_id
      or new.client_id != old.client_id
      or new.title != old.title
      or new.subtotal_cents != old.subtotal_cents
      or new.tax_rate_percent is distinct from old.tax_rate_percent
      or new.tax_cents is distinct from old.tax_cents
      or new.total_cents != old.total_cents
      or new.notes is distinct from old.notes
      or new.valid_until is distinct from old.valid_until
    then
      raise exception 'Clients may only update approved_at on a proposal';
    end if;

    new.status = 'approved';
  end if;

  return new;
end;
$$;

create trigger enforce_proposal_client_update_trigger
  before update on proposals
  for each row execute function public.enforce_proposal_client_update();

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (Section 7.2)
-- ----------------------------------------------------------------------------
alter table proposals enable row level security;

create policy "proposals_owner_pro_full_access"
  on proposals for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

create policy "proposals_client_read_own"
  on proposals for select
  to authenticated
  using (client_id = auth.uid());

-- Client update policy — the column-level restriction is enforced by the
-- trigger above, not here. This policy just gates who can attempt the
-- update at all.
create policy "proposals_client_approve_own"
  on proposals for update
  to authenticated
  using (client_id = auth.uid())
  with check (client_id = auth.uid());

create policy "admin_bypass_proposals"
  on proposals for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ============================================================================
-- End of migration
-- ============================================================================
