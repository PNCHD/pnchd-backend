-- ============================================================================
-- PNCHD · Phase 2, Block C (new this session — not yet reflected in
-- ARCHITECTURE.docx, log this table there next time it's edited)
-- Migration: widen notifications.type to cover pending-action events
-- Ref: HANDOFF.md decision — the original enum (migration 010) only covers
-- completion events (document_signed, invoice_paid, proposal_approved,
-- job_assigned, payment_received, general). There was no "something new
-- landed in your queue" type — a client got emailed by Docuseal when a
-- document was assigned to them (Section 8.1 step 4), but never got an
-- in-app notification row for it, only for the *signed* completion event.
-- Widening for all three client to-do flows at once (documents, invoices,
-- proposals) since they're the same structural gap, not just the one that
-- came up in conversation.
-- ============================================================================

alter table notifications drop constraint if exists notifications_type_check;

alter table notifications add constraint notifications_type_check check (type in (
  'document_signed',
  'invoice_paid',
  'proposal_approved',
  'job_assigned',
  'payment_received',
  'general',
  'document_pending_signature',
  'invoice_pending_payment',
  'proposal_pending_approval'
));

comment on column notifications.type is 'Section 5.1 enum, widened this session to add the three pending-action types (document_pending_signature, invoice_pending_payment, proposal_pending_approval) alongside the original completion-event types. Not yet wired to any trigger/Edge Function that actually inserts these rows on assignment — see HANDOFF.md.';

-- ============================================================================
-- End of migration
-- ============================================================================
