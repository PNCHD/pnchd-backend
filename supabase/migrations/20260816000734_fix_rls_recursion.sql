-- ============================================================================
-- PNCHD · Phase 2, Block F
-- Migration: fix infinite recursion in RLS policies
--
-- CRITICAL BUG. Every policy in the project resolved the current user's org and
-- role with an inline subquery:
--
--   organization_id = (select organization_id from profiles where id = auth.uid())
--
-- On `profiles` itself that subquery is subject to `profiles`' own SELECT
-- policy, which runs the same subquery again — unbounded. Postgres aborts with
-- 42P17 "infinite recursion detected in policy for relation profiles".
--
-- Because every other table's policy also reads `profiles`, the recursion
-- propagated everywhere: NO authenticated user could read ANY row from ANY
-- table. Verified against pnchd-dev by signing in as a real client — a plain
-- select on their own invoice returned 42P17.
--
-- This was invisible until now for the same reason as the missing GRANTs
-- (migration 20260811192313): every prior check ran as service_role, which
-- bypasses RLS entirely. See docs/ENGINEERING_NOTES.md §1.8.
--
-- Fix: resolve the current user's org and role through SECURITY DEFINER
-- helpers. Running as the function owner, they bypass RLS for that one lookup,
-- which breaks the cycle. Same technique already used by has_active_module().
-- Every policy is rewritten to use them — both to remove the recursion and so
-- there is one place to change this logic in future.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Current-user helpers
--
-- STABLE lets the planner evaluate these once per statement rather than per
-- row. search_path is pinned because SECURITY DEFINER without it lets a caller
-- shadow `profiles` from an earlier schema and hijack the owner's privileges.
-- ----------------------------------------------------------------------------
create or replace function public.current_user_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from profiles where id = auth.uid();
$$;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from profiles where id = auth.uid();
$$;

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from profiles where id = auth.uid()) = 'platform_admin',
    false
  );
$$;

create or replace function public.current_user_is_contractor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from profiles where id = auth.uid()) in ('owner', 'pro'),
    false
  );
$$;

comment on function public.current_user_organization_id is 'Current user''s organization_id, read with RLS bypassed. Policies MUST use this rather than an inline subquery on profiles — an inline subquery recurses through profiles'' own policy (42P17).';

-- ----------------------------------------------------------------------------
-- 2. organizations
-- ----------------------------------------------------------------------------
drop policy if exists "org_members_can_read_own_org" on organizations;
create policy "org_members_can_read_own_org"
  on organizations for select
  to authenticated
  using (id = current_user_organization_id());

drop policy if exists "admin_bypass_organizations" on organizations;
create policy "admin_bypass_organizations"
  on organizations for all
  to authenticated
  using (current_user_is_admin());

-- org_owner_can_update_own_org / org_owner_can_insert_own_org compare against
-- owner_id = auth.uid() and never touch profiles, so they cannot recurse.

-- ----------------------------------------------------------------------------
-- 3. profiles — the source of the recursion
-- ----------------------------------------------------------------------------
drop policy if exists "profiles_read_within_org" on profiles;
create policy "profiles_read_within_org"
  on profiles for select
  to authenticated
  using (
    id = auth.uid()
    or organization_id = current_user_organization_id()
  );

drop policy if exists "admin_bypass_profiles" on profiles;
create policy "admin_bypass_profiles"
  on profiles for all
  to authenticated
  using (current_user_is_admin());

-- profiles_update_own_row is id = auth.uid() only; no recursion.

-- ----------------------------------------------------------------------------
-- 4. module_subscriptions
-- ----------------------------------------------------------------------------
drop policy if exists "module_subscriptions_read_own_org" on module_subscriptions;
create policy "module_subscriptions_read_own_org"
  on module_subscriptions for select
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_module_subscriptions" on module_subscriptions;
create policy "admin_bypass_module_subscriptions"
  on module_subscriptions for all
  to authenticated
  using (current_user_is_admin());

-- ----------------------------------------------------------------------------
-- 5. projects
-- ----------------------------------------------------------------------------
drop policy if exists "projects_owner_pro_full_access" on projects;
create policy "projects_owner_pro_full_access"
  on projects for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_projects" on projects;
create policy "admin_bypass_projects"
  on projects for all
  to authenticated
  using (current_user_is_admin());

-- projects_client_read_own and projects_driver_read_assigned use auth.uid()
-- directly / an exists on project_assignments; neither recurses.

-- ----------------------------------------------------------------------------
-- 6. project_assignments
-- ----------------------------------------------------------------------------
drop policy if exists "project_assignments_owner_pro_full_access" on project_assignments;
create policy "project_assignments_owner_pro_full_access"
  on project_assignments for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_project_assignments" on project_assignments;
create policy "admin_bypass_project_assignments"
  on project_assignments for all
  to authenticated
  using (current_user_is_admin());

-- ----------------------------------------------------------------------------
-- 7. proposals
-- ----------------------------------------------------------------------------
drop policy if exists "proposals_owner_pro_full_access" on proposals;
create policy "proposals_owner_pro_full_access"
  on proposals for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_proposals" on proposals;
create policy "admin_bypass_proposals"
  on proposals for all
  to authenticated
  using (current_user_is_admin());

-- ----------------------------------------------------------------------------
-- 8. invoices
-- ----------------------------------------------------------------------------
drop policy if exists "invoices_owner_pro_full_access" on invoices;
create policy "invoices_owner_pro_full_access"
  on invoices for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_invoices" on invoices;
create policy "admin_bypass_invoices"
  on invoices for all
  to authenticated
  using (current_user_is_admin());

-- ----------------------------------------------------------------------------
-- 9. line_items
-- ----------------------------------------------------------------------------
drop policy if exists "line_items_owner_pro_full_access" on line_items;
create policy "line_items_owner_pro_full_access"
  on line_items for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_line_items" on line_items;
create policy "admin_bypass_line_items"
  on line_items for all
  to authenticated
  using (current_user_is_admin());

-- ----------------------------------------------------------------------------
-- 10. documents / document_signers
-- ----------------------------------------------------------------------------
drop policy if exists "documents_owner_pro_full_access" on documents;
create policy "documents_owner_pro_full_access"
  on documents for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_documents" on documents;
create policy "admin_bypass_documents"
  on documents for all
  to authenticated
  using (current_user_is_admin());

drop policy if exists "document_signers_owner_pro_full_access" on document_signers;
create policy "document_signers_owner_pro_full_access"
  on document_signers for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_document_signers" on document_signers;
create policy "admin_bypass_document_signers"
  on document_signers for all
  to authenticated
  using (current_user_is_admin());

-- ----------------------------------------------------------------------------
-- 11. vehicles / vehicle_locations
-- ----------------------------------------------------------------------------
drop policy if exists "vehicles_owner_pro_full_access" on vehicles;
create policy "vehicles_owner_pro_full_access"
  on vehicles for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "admin_bypass_vehicles" on vehicles;
create policy "admin_bypass_vehicles"
  on vehicles for all
  to authenticated
  using (current_user_is_admin());

drop policy if exists "vehicle_locations_owner_pro_read" on vehicle_locations;
create policy "vehicle_locations_owner_pro_read"
  on vehicle_locations for select
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
    and has_active_module('fleet_tracking')
  );

drop policy if exists "vehicle_locations_driver_insert_own" on vehicle_locations;
create policy "vehicle_locations_driver_insert_own"
  on vehicle_locations for insert
  to authenticated
  with check (
    organization_id = current_user_organization_id()
    and driver_id = auth.uid()
    and has_active_module('fleet_tracking')
  );

drop policy if exists "admin_bypass_vehicle_locations" on vehicle_locations;
create policy "admin_bypass_vehicle_locations"
  on vehicle_locations for all
  to authenticated
  using (current_user_is_admin());

-- ----------------------------------------------------------------------------
-- 12. notifications
-- ----------------------------------------------------------------------------
drop policy if exists "admin_bypass_notifications" on notifications;
create policy "admin_bypass_notifications"
  on notifications for all
  to authenticated
  using (current_user_is_admin());

-- notifications_read_own / notifications_update_own are recipient_id =
-- auth.uid() only; no recursion.

-- ----------------------------------------------------------------------------
-- 13. client_feature_toggles
-- ----------------------------------------------------------------------------
drop policy if exists "client_feature_toggles_owner_pro_full_access" on client_feature_toggles;
create policy "client_feature_toggles_owner_pro_full_access"
  on client_feature_toggles for all
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  )
  with check (
    organization_id = current_user_organization_id()
    and current_user_is_contractor()
  );

drop policy if exists "client_feature_toggles_client_read_own_org" on client_feature_toggles;
create policy "client_feature_toggles_client_read_own_org"
  on client_feature_toggles for select
  to authenticated
  using (
    organization_id = current_user_organization_id()
    and current_user_role() = 'client'
  );

drop policy if exists "admin_bypass_client_feature_toggles" on client_feature_toggles;
create policy "admin_bypass_client_feature_toggles"
  on client_feature_toggles for all
  to authenticated
  using (current_user_is_admin());

-- ----------------------------------------------------------------------------
-- 14. Enforcement triggers resolve the caller's role the same way
-- ----------------------------------------------------------------------------
create or replace function public.enforce_invoice_client_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user_role() = 'client' then
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

-- ============================================================================
-- End of migration
-- ============================================================================
