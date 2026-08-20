-- ============================================================================
-- PNCHD · Phase 2, Block I
-- Migration: fix client-write triggers that never fired
--
-- SECURITY BUG. The enforcement triggers on proposals and document_signers
-- declared a PL/pgSQL variable named `current_role`:
--
--   declare current_role text;
--   begin
--     select role into current_role from profiles where id = auth.uid();
--     if current_role = 'client' then ... raise exception ... end if;
--
-- `current_role` is a RESERVED SQL keyword in Postgres that evaluates to the
-- current SQL role name — here `authenticated`. The keyword wins over the
-- declared variable, so the condition compared 'authenticated' = 'client' and
-- was always false. The trigger body never executed. No error, no warning: the
-- triggers existed, fired, and silently did nothing.
--
-- Confirmed against pnchd-dev by signing in as a real client:
--   * approved a proposal that had never been sent
--   * rewrote a $1,000.00 proposal's total_cents to 1 ($0.01) while approving it
--   * status was never auto-flipped to 'approved', because that line is inside
--     the same dead branch
--
-- The invoices copy of this trigger was already rewritten (incidentally, while
-- fixing RLS recursion in 20260816000734) to call current_user_role(), which is
-- why invoice enforcement worked and these two did not.
--
-- Fix: use the current_user_role() helper. As a plain function call it cannot
-- collide with a keyword, and it is the same helper every policy now uses.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. proposals — client may set approved_at only, on a sent proposal
-- ----------------------------------------------------------------------------
create or replace function public.enforce_proposal_client_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user_role() = 'client' then
    if old.status != 'sent' then
      raise exception 'Proposal must be in sent status to be approved';
    end if;

    if new.approved_at is null or old.approved_at is not null then
      raise exception 'Clients may only set approved_at once, on a sent proposal';
    end if;

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

-- ----------------------------------------------------------------------------
-- 2. document_signers — signer may set signed_at once
-- ----------------------------------------------------------------------------
create or replace function public.enforce_document_signer_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user_role() in ('client', 'driver') then
    if new.signed_at is null or old.signed_at is not null then
      raise exception 'Signers may only set signed_at once';
    end if;

    if new.document_id != old.document_id
      or new.organization_id != old.organization_id
      or new.profile_id is distinct from old.profile_id
      or new.signer_name != old.signer_name
      or new.signer_email != old.signer_email
      or new.docuseal_submitter_id is distinct from old.docuseal_submitter_id
      or new.signing_ip is distinct from old.signing_ip
    then
      raise exception 'Signers may only update signed_at on their own record';
    end if;

    new.status = 'signed';
  end if;

  return new;
end;
$$;

-- ============================================================================
-- End of migration
-- ============================================================================
