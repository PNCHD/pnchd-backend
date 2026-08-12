-- ============================================================================
-- PNCHD · Phase 2, Block C (new this session — not yet reflected in
-- ARCHITECTURE.docx, log this table there next time it's edited)
-- Migration: client_feature_toggles
-- Ref: HANDOFF.md decision — client-facing capabilities (pay invoices, sign
-- documents, messaging) need an owner-controlled on/off switch independent
-- of module billing status. A org can be actively subscribed+billed for
-- document_signing (so the owner can use it) while still choosing not to
-- expose it to clients yet — module_subscriptions.is_active alone can't
-- express that, since it's purely a billing-sync mirror of Stripe.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. client_feature_toggles
-- One row per org+feature_key. feature_key intentionally reuses the same
-- key names as the overlapping module_key values (client_payments,
-- document_signing) so the relationship is obvious: is_enabled here is a
-- second, independent gate layered on top of "is this module even active."
-- messaging is included even though it's a roadmap module (Section 2.2) —
-- the toggle can exist before the module ships, it'll just have no effect
-- until messaging is built.
-- ----------------------------------------------------------------------------
create table if not exists client_feature_toggles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  feature_key text not null check (feature_key in (
    'client_payments',
    'document_signing',
    'messaging'
  )),
  is_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

comment on table client_feature_toggles is 'Owner-controlled on/off switch for client-facing capabilities, independent of module_subscriptions.is_active (billing). Added this session — not yet in ARCHITECTURE.docx.';
comment on column client_feature_toggles.feature_key is 'Reuses module_subscriptions.module_key naming for the overlapping keys (client_payments, document_signing) — this is a second gate on top of the module being active, not a replacement for it.';

create trigger set_client_feature_toggles_updated_at
  before update on client_feature_toggles
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2. Indexes
-- Not a Section 6 table (doesn't exist in the doc yet), so no "follow
-- Section 6 exactly" constraint here. This unique index both serves the
-- only real access pattern (org_id + feature_key) and enforces the "one
-- row per feature per org" invariant — a correctness constraint, not just
-- a performance add.
-- ----------------------------------------------------------------------------
create unique index if not exists idx_client_feature_toggles_org_feature
  on client_feature_toggles (organization_id, feature_key);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security
-- Owner/Pro: full CRUD on own org (they're the ones flipping the switch).
-- Client: read-only on own org's toggles — the client app needs to check
-- these to know what to show, same reasoning as has_active_module().
--
-- NOTE — not yet wired into enforcement: the existing client-facing RLS
-- policies on invoices/documents (migrations 006/008) don't check this
-- table. Today, a client can still approve/pay an invoice or sign a
-- document via direct table access regardless of this toggle — it only
-- gates what the client app's UI chooses to show. Flagging rather than
-- silently deciding: extending those policies to also require
-- `is_client_feature_enabled(...)` is a real follow-up, not done here.
-- ----------------------------------------------------------------------------
alter table client_feature_toggles enable row level security;

create policy "client_feature_toggles_owner_pro_full_access"
  on client_feature_toggles for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

create policy "client_feature_toggles_client_read_own_org"
  on client_feature_toggles for select
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) = 'client'
  );

create policy "admin_bypass_client_feature_toggles"
  on client_feature_toggles for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ----------------------------------------------------------------------------
-- 4. Reusable check, mirroring has_active_module() (migration 002)
-- ----------------------------------------------------------------------------
create or replace function public.is_client_feature_enabled(check_feature_key text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((
    select is_enabled from client_feature_toggles
    where organization_id = (select organization_id from profiles where id = auth.uid())
    and feature_key = check_feature_key
  ), false);
$$;

comment on function public.is_client_feature_enabled is 'Checks whether the current user''s org has enabled the given client-facing feature. Defaults to false (no row = not enabled) so a feature is opt-in, not opt-out.';

-- ============================================================================
-- End of migration
-- ============================================================================
