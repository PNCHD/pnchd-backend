-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: notifications
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. notifications
-- In-app notifications for all user tiers. Push delivery is handled
-- separately via FCM (Section 8.4) — this table drives the in-app inbox
-- and unread badge only.
-- ----------------------------------------------------------------------------
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  recipient_id uuid not null references profiles(id),
  title text not null,
  body text not null,
  type text not null check (type in (
    'document_signed',
    'invoice_paid',
    'proposal_approved',
    'job_assigned',
    'payment_received',
    'general'
  )),
  reference_type text,
  reference_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table notifications is 'In-app notifications for all user tiers. Section 5.1. Inserted by the FCM-sending Edge Function (Section 8.4) via the service role key, not by regular users.';
comment on column notifications.reference_type is 'e.g. invoice, document — identifies which table reference_id points into.';
comment on column notifications.reference_id is 'ID of the related record, per reference_type. No FK possible since it points into multiple tables.';

-- ----------------------------------------------------------------------------
-- 2. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_notifications_recipient_is_read
  on notifications (recipient_id, is_read);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security (Section 7.2)
-- Every tier: read and update own notifications only (recipient_id = self).
-- No org-wide read for owner/pro — unlike every other table, this one is
-- scoped to the individual recipient, not the organization. No insert or
-- delete policy for regular users on purpose: rows are written exclusively
-- by the FCM Edge Function using the service role key, which bypasses RLS
-- entirely — same reasoning as module_subscriptions (migration 002).
-- ----------------------------------------------------------------------------
alter table notifications enable row level security;

create policy "notifications_read_own"
  on notifications for select
  to authenticated
  using (recipient_id = auth.uid());

create policy "notifications_update_own"
  on notifications for update
  to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

create policy "admin_bypass_notifications"
  on notifications for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ============================================================================
-- End of migration
-- ============================================================================
