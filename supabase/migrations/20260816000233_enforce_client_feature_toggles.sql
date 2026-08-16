-- ============================================================================
-- PNCHD · Phase 2, Block F
-- Migration: enforce client_feature_toggles in RLS
-- Ref: ARCHITECTURE.md Section 5.2 gap #3 — resolved. Hard block: a client with
-- a document already sent to them cannot finish signing once the owner
-- disables the feature. No grandfathering of in-flight items.
--
-- Until now the toggle only controlled what the client app chose to render, so
-- a client could still pay or sign through direct API access. This closes that.
--
-- Writes only. Read policies are left alone deliberately: hiding rows a client
-- previously saw would break their history and audit trail, and the client app
-- already hides the entry points. The toggle gates *doing the thing*, not
-- seeing that it exists.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. document_signers — signing requires client-facing document_signing on
--
-- Dropped and recreated rather than altered: Postgres has no ALTER POLICY that
-- can AND a new condition into an existing one.
-- ----------------------------------------------------------------------------
drop policy if exists "document_signers_own_record_update" on document_signers;

create policy "document_signers_own_record_update"
  on document_signers for update
  to authenticated
  using (
    profile_id = auth.uid()
    and is_client_feature_enabled('document_signing')
  )
  with check (
    profile_id = auth.uid()
    and is_client_feature_enabled('document_signing')
  );

-- ----------------------------------------------------------------------------
-- 2. invoices — client approval requires client-facing client_payments on
--
-- Note this gates the client's sent -> approved transition only. `paid` is
-- unreachable from here regardless: it is set exclusively by the
-- payment_intent.succeeded Edge Function using the service role, which
-- bypasses RLS entirely. Turning the toggle off mid-flow therefore cannot
-- strand an already-captured payment.
-- ----------------------------------------------------------------------------
drop policy if exists "invoices_client_approve_own" on invoices;

create policy "invoices_client_approve_own"
  on invoices for update
  to authenticated
  using (
    client_id = auth.uid()
    and is_client_feature_enabled('client_payments')
  )
  with check (
    client_id = auth.uid()
    and is_client_feature_enabled('client_payments')
  );

-- Proposals are deliberately untouched. Proposal approval maps to no
-- feature_key in client_feature_toggles (the enum covers client_payments,
-- document_signing, messaging), and per the Section 5.2 gap #1 decision there
-- is no client rejection path either — a client who does not want to proceed
-- simply does not approve, and handles it with the contractor directly.

-- ============================================================================
-- End of migration
-- ============================================================================
