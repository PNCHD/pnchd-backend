import type { SupabaseClient } from "@supabase/supabase-js";

export type WebhookProvider = "stripe" | "docuseal";

/**
 * Wraps the webhook_events ledger (migration 20260811192107). See
 * ARCHITECTURE.md Section 8.5 — providers retry and duplicate deliveries, and
 * side effects like notification inserts are not idempotent on their own.
 */

/** Returns true if the caller should process this event. */
export async function claimEvent(
  admin: SupabaseClient,
  provider: WebhookProvider,
  eventId: string,
  eventType: string,
): Promise<boolean> {
  const { data, error } = await admin.rpc("claim_webhook_event", {
    p_provider: provider,
    p_event_id: eventId,
    p_event_type: eventType,
  });
  if (error) throw new Error(`claim_webhook_event failed: ${error.message}`);
  return data === true;
}

export async function completeEvent(
  admin: SupabaseClient,
  provider: WebhookProvider,
  eventId: string,
): Promise<void> {
  const { error } = await admin.rpc("complete_webhook_event", {
    p_provider: provider,
    p_event_id: eventId,
  });
  if (error) console.error(`complete_webhook_event failed: ${error.message}`);
}

/**
 * Marking failed (rather than deleting) keeps the attempt count and lets the
 * next provider retry re-claim it. A swallowed error here is intentional — we
 * are already on the failure path and the response status is what actually
 * drives the retry.
 */
export async function failEvent(
  admin: SupabaseClient,
  provider: WebhookProvider,
  eventId: string,
  message: string,
): Promise<void> {
  const { error } = await admin.rpc("fail_webhook_event", {
    p_provider: provider,
    p_event_id: eventId,
    p_error_message: message.slice(0, 1000),
  });
  if (error) console.error(`fail_webhook_event failed: ${error.message}`);
}
