-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: module_subscriptions
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2/7.3 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. module_subscriptions
-- Tracks which modules an organization has active. Synced from Stripe via
-- Edge Function webhook (Section 8.2, customer.subscription.updated).
-- ----------------------------------------------------------------------------
create table if not exists module_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  module_key text not null check (module_key in (
    'scheduling',
    'document_signing',
    'proposals_invoicing',
    'client_payments',
    'fleet_tracking',
    'messaging',
    'budget_tracking',
    'file_storage',
    'multi_contractor',
    'client_portal'
  )),
  stripe_subscription_item_id text,
  is_active boolean not null default true,
  activated_at timestamptz not null default now(),
  deactivated_at timestamptz
);

comment on table module_subscriptions is 'Which modules an org has active. Synced from Stripe via customer.subscription.updated webhook. Section 8.2.';
comment on column module_subscriptions.stripe_subscription_item_id is 'Links to the Stripe Subscription Item. NULL for founding members on the flat-rate price, since they are not billed per module (Section 2.3).';

-- One active row per org+module — prevents duplicate active subscriptions
-- to the same module from a webhook race or retry.
create unique index if not exists idx_module_subscriptions_org_module_active
  on module_subscriptions (organization_id, module_key)
  where is_active = true;

-- ----------------------------------------------------------------------------
-- 2. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_module_subscriptions_org_key
  on module_subscriptions (organization_id, module_key);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security
-- Section 7.2: Owner/Pro read only. Client/Driver no access.
-- Writes happen exclusively via the webhook Edge Function using the
-- service role key, which bypasses RLS entirely — so there is no insert/
-- update/delete policy for regular users here on purpose.
-- ----------------------------------------------------------------------------
alter table module_subscriptions enable row level security;

create policy "module_subscriptions_read_own_org"
  on module_subscriptions for select
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

create policy "admin_bypass_module_subscriptions"
  on module_subscriptions for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ----------------------------------------------------------------------------
-- 4. Reusable module-gating check (Section 7.3)
--
-- Rather than repeating the EXISTS subquery from Section 7.3 inline on every
-- module-specific table's RLS policy, wrap it in a function. Future policies
-- (vehicle_locations, messaging tables, etc.) call this instead of
-- duplicating the subquery — one place to fix if the gating logic changes.
--
-- Usage in a future policy:
--   using ( organization_id = ... and has_active_module('fleet_tracking') )
-- ----------------------------------------------------------------------------
create or replace function public.has_active_module(check_module_key text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from module_subscriptions
    where organization_id = (select organization_id from profiles where id = auth.uid())
    and module_key = check_module_key
    and is_active = true
  );
$$;

comment on function public.has_active_module is 'Checks whether the current user''s org has an active subscription to the given module. Use in RLS policies for module-gated tables per Section 7.3.';

-- ============================================================================
-- End of migration
-- ============================================================================
