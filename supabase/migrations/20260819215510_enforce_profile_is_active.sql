-- ============================================================================
-- PNCHD · Phase 2, Block J
-- Migration: make profiles.is_active actually deactivate
--
-- SECURITY BUG. `profiles.is_active` exists (migration 001) and Section 5.1
-- describes it as "set false to deactivate without deleting". No policy or
-- helper function has ever referenced it. Deactivating a user did nothing: they
-- kept their session, kept passing every policy, and retained exactly the access
-- they had before.
--
-- Worst case is a departed seat, who has full CRUD on every project, client,
-- proposal, invoice and document in the organization.
--
-- Same family as the dead enforcement triggers (20260819181016): a control that
-- exists, appears to work in the UI, and enforces nothing.
--
-- Fix: a RESTRICTIVE policy per table. Restrictive policies AND with everything
-- else (ARCHITECTURE.md 7.4, ACCESS_MODEL.md 2.3), so this cannot be widened by
-- any existing or future permissive policy — including admin_bypass, and
-- including policies that compare auth.uid() directly and would otherwise
-- sidestep the current_user_* helpers entirely.
--
-- Edge Functions are unaffected: the service role bypasses RLS.
-- ============================================================================

create or replace function public.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_active from profiles where id = auth.uid()), false);
$$;

comment on function public.current_user_is_active is 'False for a deactivated or unknown profile. Enforced as a restrictive policy on every table, so deactivation revokes access everywhere at once.';

revoke execute on function public.current_user_is_active() from anon;

-- ----------------------------------------------------------------------------
-- Restrictive gate on every table holding organization data.
--
-- profiles is included: a deactivated user must not read the directory either.
-- Their own row stays readable only because they cannot get past this at all,
-- which is the intent — deactivated means no access, not reduced access.
-- ----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'organizations', 'profiles', 'module_subscriptions', 'projects',
    'project_assignments', 'proposals', 'invoices', 'line_items',
    'documents', 'document_signers', 'vehicles', 'vehicle_locations',
    'notifications', 'client_feature_toggles'
  ]
  loop
    execute format('drop policy if exists %I on %I', 'require_active_profile_' || t, t);
    execute format(
      'create policy %I on %I as restrictive for all to authenticated using (current_user_is_active())',
      'require_active_profile_' || t, t
    );
  end loop;
end;
$$;

-- ============================================================================
-- End of migration
-- ============================================================================
