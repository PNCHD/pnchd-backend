-- ============================================================================
-- PNCHD · Phase 2, Block F
-- Migration: in-app notifications when work is assigned to a client
-- Ref: ARCHITECTURE.md Section 5.2 gap #4 — partially resolved.
--
-- The *_pending_* enum values existed but nothing wrote them, so a client got
-- Docuseal's email and nothing else — no in-app badge for an invoice to pay or
-- a proposal to approve at all.
--
-- Implemented as database triggers rather than in the Edge Functions on
-- purpose: the notification should fire whichever path sends the item (mobile,
-- web, an Edge Function, or a manual dashboard update), and a trigger is the
-- only place that covers all of them. Section 8.4 assigns this to an Edge
-- Function because it also assumed the FCM push happened there — see the note
-- at the end for what is still outstanding.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Org-scoped feature check
--
-- is_client_feature_enabled() resolves the org from auth.uid(), which inside
-- these triggers is the *contractor* performing the update, not the client
-- receiving the notification. This variant takes the org explicitly.
-- ----------------------------------------------------------------------------
create or replace function public.is_client_feature_enabled_for_org(
  p_organization_id uuid,
  p_feature_key text
)
returns boolean
language sql
stable
as $$
  select coalesce((
    select is_enabled from client_feature_toggles
    where organization_id = p_organization_id
    and feature_key = p_feature_key
  ), false);
$$;

comment on function public.is_client_feature_enabled_for_org is 'Org-scoped variant of is_client_feature_enabled(), for trigger contexts where auth.uid() is not the client.';

revoke execute on function public.is_client_feature_enabled_for_org(uuid, text)
  from anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. Invoice sent -> client owes a payment
--
-- Guarded on the client_payments toggle: with it off the client is hard-blocked
-- from approving (previous migration), so notifying them would be handing them
-- a to-do they cannot action.
-- ----------------------------------------------------------------------------
create or replace function public.notify_invoice_sent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'sent'
     and old.status is distinct from 'sent'
     and is_client_feature_enabled_for_org(new.organization_id, 'client_payments')
  then
    insert into notifications (
      organization_id, recipient_id, title, body, type, reference_type, reference_id
    ) values (
      new.organization_id,
      new.client_id,
      'Invoice ready to pay',
      coalesce(new.title, 'An invoice') || ' is ready for payment.',
      'invoice_pending_payment',
      'invoice',
      new.id
    );
  end if;
  return new;
end;
$$;

create trigger notify_invoice_sent_trigger
  after update on invoices
  for each row execute function public.notify_invoice_sent();

-- ----------------------------------------------------------------------------
-- 3. Proposal sent -> client owes an approval
--
-- Unguarded: proposal approval maps to no feature_key in
-- client_feature_toggles, so there is no toggle that could disable it.
-- ----------------------------------------------------------------------------
create or replace function public.notify_proposal_sent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'sent' and old.status is distinct from 'sent' then
    insert into notifications (
      organization_id, recipient_id, title, body, type, reference_type, reference_id
    ) values (
      new.organization_id,
      new.client_id,
      'Proposal ready for review',
      coalesce(new.title, 'A proposal') || ' is ready for your approval.',
      'proposal_pending_approval',
      'proposal',
      new.id
    );
  end if;
  return new;
end;
$$;

create trigger notify_proposal_sent_trigger
  after update on proposals
  for each row execute function public.notify_proposal_sent();

-- ----------------------------------------------------------------------------
-- 4. Signer invited -> client owes a signature
--
-- Fires on both INSERT and UPDATE: a signer row may be created already in
-- 'sent' state, or created as 'pending' and moved to 'sent' later.
--
-- profile_id is null for external signers who have no PNCHD account. They get
-- Docuseal's email (Section 8.1 step 4); there is no in-app inbox to write to.
-- ----------------------------------------------------------------------------
create or replace function public.notify_signer_invited()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_document_title text;
begin
  if new.profile_id is null then
    return new;
  end if;

  if new.status = 'sent'
     and (tg_op = 'INSERT' or old.status is distinct from 'sent')
     and is_client_feature_enabled_for_org(new.organization_id, 'document_signing')
  then
    select title into v_document_title from documents where id = new.document_id;

    insert into notifications (
      organization_id, recipient_id, title, body, type, reference_type, reference_id
    ) values (
      new.organization_id,
      new.profile_id,
      'Document ready to sign',
      coalesce(v_document_title, 'A document') || ' is waiting for your signature.',
      'document_pending_signature',
      'document',
      new.document_id
    );
  end if;
  return new;
end;
$$;

create trigger notify_signer_invited_trigger
  after insert or update on document_signers
  for each row execute function public.notify_signer_invited();

-- ----------------------------------------------------------------------------
-- STILL OUTSTANDING: FCM push delivery (Section 8.4 step 3).
--
-- These triggers create the in-app notification rows only. Actually pushing to
-- a device needs the FCM HTTP v1 API, which requires a Google service account
-- and OAuth2 tokens — the FCM_SERVER_KEY in Section 11.2 refers to the legacy
-- API Google has deprecated. Blocked on Firebase project setup, not on this
-- schema.
-- ----------------------------------------------------------------------------

-- ============================================================================
-- End of migration
-- ============================================================================
