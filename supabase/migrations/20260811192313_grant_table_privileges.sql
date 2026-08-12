-- ============================================================================
-- PNCHD · Phase 2, Block D
-- Migration: grant table/function privileges to the API roles
--
-- BUG FIX. Migrations 001–014 enabled RLS and wrote policies but never granted
-- SQL table privileges. GRANT and RLS are two independent gates and a request
-- must pass BOTH — so every table was unreachable by every role, including
-- service_role. Verified against pnchd-dev: PostgREST returned 42501
-- "permission denied for table profiles" for a service_role request.
--
-- Supabase normally handles this via ALTER DEFAULT PRIVILEGES for tables
-- created by the `postgres` role; the role `supabase db push` connects as did
-- not pick those up, so nothing was granted.
--
-- Security model is unchanged: the broad grants to anon/authenticated are the
-- standard Supabase pattern, because RLS — not table privileges — is the
-- enforcement layer. A table with RLS enabled and no matching policy denies by
-- default regardless of its grants.
-- ============================================================================

grant usage on schema public to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. Existing objects
-- ----------------------------------------------------------------------------
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Future objects — so a new table isn't dead on arrival like these were
-- ----------------------------------------------------------------------------
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Claw back what the client roles should never touch
--
-- Defense in depth. RLS already denies these (webhook_events has zero policies,
-- and the webhook functions are only called by Edge Functions holding the
-- service-role key), but removing the grant means a policy added by mistake
-- later still can't expose operational plumbing to a client.
-- ----------------------------------------------------------------------------
revoke all on table webhook_events from anon, authenticated;

revoke execute on function public.claim_webhook_event(text, text, text, interval)
  from anon, authenticated;
revoke execute on function public.complete_webhook_event(text, text)
  from anon, authenticated;
revoke execute on function public.fail_webhook_event(text, text, text)
  from anon, authenticated;

-- ============================================================================
-- End of migration
-- ============================================================================
