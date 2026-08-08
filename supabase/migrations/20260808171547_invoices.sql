-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: invoices
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. invoices
-- ----------------------------------------------------------------------------
create table if not exists invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  project_id uuid references projects(id),
  proposal_id uuid references proposals(id),
  client_id uuid not null references profiles(id),
  title text not null,
  stripe_payment_intent_id text,
  subtotal_cents integer not null default 0,
  tax_cents integer,
  total_cents integer not null default 0,
  status text not null default 'draft' check (status in (
    'draft', 'sent', 'approved', 'paid', 'voided', 'refunded'
  )),
  due_date date,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

comment on column invoices.proposal_id is 'Set if this invoice was converted from a proposal.';
comment on column invoices.subtotal_cents is 'Money always stored in cents, never floats.';

-- ----------------------------------------------------------------------------
-- 2. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_invoices_org_client
  on invoices (organization_id, client_id);

create index if not exists idx_invoices_status
  on invoices (status);

-- ----------------------------------------------------------------------------
-- 3. Client approval restriction
--
-- Section 7.2: clients may "write approval status only" — read as: move
-- status from 'sent' to 'approved'. Actual payment (status -> 'paid') is
-- Stripe-driven, via the payment_intent.succeeded webhook using the
-- service role key (Section 8.3), never a direct client write. This
-- trigger keeps clients from writing status = 'paid' themselves.
-- ----------------------------------------------------------------------------
create or replace function public.enforce_invoice_client_update()
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
    if old.status != 'sent' or new.status != 'approved' then
      raise exception 'Clients may only move an invoice from sent to approved';
    end if;

    if new.organization_id != old.organization_id
      or new.project_id is distinct from old.project_id
      or new.proposal_id is distinct from old.proposal_id
      or new.client_id != old.client_id
      or new.title != old.title
      or new.stripe_payment_intent_id is distinct from old.stripe_payment_intent_id
      or new.subtotal_cents != old.subtotal_cents
      or new.tax_cents is distinct from old.tax_cents
      or new.total_cents != old.total_cents
      or new.due_date is distinct from old.due_date
      or new.paid_at is distinct from old.paid_at
    then
      raise exception 'Clients may only update status on an invoice';
    end if;
  end if;

  return new;
end;
$$;

create trigger enforce_invoice_client_update_trigger
  before update on invoices
  for each row execute function public.enforce_invoice_client_update();

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (Section 7.2)
-- ----------------------------------------------------------------------------
alter table invoices enable row level security;

create policy "invoices_owner_pro_full_access"
  on invoices for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

create policy "invoices_client_read_own"
  on invoices for select
  to authenticated
  using (client_id = auth.uid());

create policy "invoices_client_approve_own"
  on invoices for update
  to authenticated
  using (client_id = auth.uid())
  with check (client_id = auth.uid());

create policy "admin_bypass_invoices"
  on invoices for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ============================================================================
-- End of migration
-- ============================================================================
