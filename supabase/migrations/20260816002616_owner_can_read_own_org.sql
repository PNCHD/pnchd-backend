-- ============================================================================
-- PNCHD · Phase 2, Block G
-- Migration: let an owner read the organization they own
--
-- BUG FIX — signup was impossible. The organizations SELECT policy only
-- allowed:
--
--   id = current_user_organization_id()
--
-- which resolves through profiles.organization_id. During signup that column is
-- still NULL (handle_new_user leaves it for the signup flow to fill in), so a
-- brand-new owner could not see the organization they had just created — and
-- therefore could not read back its id to attach themselves to it.
--
-- The failure was easy to misread. INSERT ... RETURNING applies the SELECT
-- policy to the returned row, so `insert(...).select('id')` failed with
--
--   42501  new row violates row-level security policy for table "organizations"
--
-- which points at WITH CHECK. WITH CHECK passed: the same insert without
-- .select() succeeded and wrote the row. It was the RETURNING that was denied.
--
-- Fix: ownership is sufficient on its own. owner_id exists precisely to express
-- this, and it does not depend on profile attachment, so it also breaks the
-- circular dependency.
-- ============================================================================

drop policy if exists "org_members_can_read_own_org" on organizations;

create policy "org_members_can_read_own_org"
  on organizations for select
  to authenticated
  using (
    owner_id = auth.uid()
    or id = current_user_organization_id()
  );

comment on policy "org_members_can_read_own_org" on organizations is 'Owner sees the org they own even before their profile is attached (required for signup); everyone else sees the org their profile points at.';

-- ============================================================================
-- End of migration
-- ============================================================================
