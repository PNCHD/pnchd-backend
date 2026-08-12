-- ============================================================================
-- PNCHD · Phase 2, Block D
-- Migration: webhook_events (inbound webhook idempotency ledger)
-- Ref: ARCHITECTURE.md Section 8.5 (webhook handling conventions)
-- ============================================================================

create table if not exists webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('stripe', 'docuseal')),
  event_id text not null,
  event_type text,
  status text not null default 'processing'
    check (status in ('processing', 'completed', 'failed')),
  attempts integer not null default 1,
  error_message text,
  received_at timestamptz not null default now(),
  completed_at timestamptz
);

comment on table webhook_events is 'Idempotency ledger for inbound third-party webhooks. Providers retry (Stripe for up to 3 days) and may deliver duplicates; processing an event twice would double-apply non-idempotent side effects like notification inserts. Grows unbounded — a periodic cleanup of completed rows older than ~90 days should be added before launch.';
comment on column webhook_events.event_id is 'The provider''s own event identifier (Stripe evt_..., Docuseal submission event id). Unique per provider.';
comment on column webhook_events.attempts is 'Incremented each time a previously-failed or stale-processing event is re-claimed.';

create unique index if not exists idx_webhook_events_provider_event
  on webhook_events (provider, event_id);

-- ----------------------------------------------------------------------------
-- Row Level Security
-- Service-role only — Edge Functions bypass RLS entirely. No policies for
-- regular users on purpose, same reasoning as module_subscriptions. Not even
-- admin_bypass: this is operational plumbing, not org data the Section 15.3
-- dashboard needs.
-- ----------------------------------------------------------------------------
alter table webhook_events enable row level security;

-- ----------------------------------------------------------------------------
-- claim_webhook_event
--
-- Returns true if the caller should process this event, false if it's already
-- handled or in flight.
--
-- Single atomic statement rather than SELECT-then-INSERT: two concurrent
-- deliveries of the same event would both pass a separate SELECT and both
-- proceed. The unique index plus ON CONFLICT makes exactly one win.
--
-- The stale_after clause exists because a function that crashes mid-processing
-- would otherwise leave its row stuck in 'processing' forever, causing every
-- subsequent retry to be skipped — silently losing the event. Allowing reclaim
-- after a window trades a small double-processing risk for not dropping events,
-- which is the right side of that tradeoff.
-- ----------------------------------------------------------------------------
create or replace function public.claim_webhook_event(
  p_provider text,
  p_event_id text,
  p_event_type text default null,
  p_stale_after interval default interval '5 minutes'
)
returns boolean
language plpgsql
as $$
declare
  v_claimed boolean;
begin
  insert into webhook_events (provider, event_id, event_type, status)
  values (p_provider, p_event_id, p_event_type, 'processing')
  on conflict (provider, event_id) do update
    set status = 'processing',
        attempts = webhook_events.attempts + 1,
        received_at = now(),
        error_message = null
    where webhook_events.status = 'failed'
       or (webhook_events.status = 'processing'
           and webhook_events.received_at < now() - p_stale_after)
  returning true into v_claimed;

  return coalesce(v_claimed, false);
end;
$$;

comment on function public.claim_webhook_event is 'Atomically claims an inbound webhook event. Returns true to proceed, false if already completed or currently in flight. See ARCHITECTURE.md Section 8.5.';

create or replace function public.complete_webhook_event(
  p_provider text,
  p_event_id text
)
returns void
language sql
as $$
  update webhook_events
  set status = 'completed', completed_at = now(), error_message = null
  where provider = p_provider and event_id = p_event_id;
$$;

-- Marking failed (rather than deleting the row) preserves the attempt count
-- and lets claim_webhook_event re-claim it on the provider's next retry.
create or replace function public.fail_webhook_event(
  p_provider text,
  p_event_id text,
  p_error_message text
)
returns void
language sql
as $$
  update webhook_events
  set status = 'failed', error_message = p_error_message
  where provider = p_provider and event_id = p_event_id;
$$;

-- ============================================================================
-- End of migration
-- ============================================================================
