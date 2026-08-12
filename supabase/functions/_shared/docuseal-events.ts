/**
 * Pure parsing/derivation for Docuseal webhook payloads, separated from IO so
 * it can be unit tested.
 */

export interface DocusealPayload {
  event_type?: string;
  timestamp?: string;
  data?: {
    id?: number | string;
    email?: string;
    status?: string;
    completed_at?: string;
    submission_id?: number | string;
    submission?: { id?: number | string };
    [key: string]: unknown;
  };
}

export interface DocusealEvent {
  eventType: string;
  submitterId?: string;
  submissionId?: string;
  email?: string;
  completedAt?: string;
}

export function parseDocusealEvent(payload: DocusealPayload): DocusealEvent | null {
  const eventType = payload.event_type;
  if (!eventType) return null;

  const data = payload.data ?? {};
  const submissionId = data.submission_id ?? data.submission?.id;

  return {
    eventType,
    submitterId: data.id != null ? String(data.id) : undefined,
    submissionId: submissionId != null ? String(submissionId) : undefined,
    email: typeof data.email === "string" ? data.email : undefined,
    completedAt: typeof data.completed_at === "string" ? data.completed_at : undefined,
  };
}

/**
 * Docuseal payloads carry no dedicated event id, so the idempotency key is
 * derived from the fields that make a delivery unique. Including `timestamp`
 * keeps genuinely distinct events (viewed, then completed) from colliding,
 * while a duplicate delivery of the same event reproduces the same key.
 */
export function docusealEventKey(
  payload: DocusealPayload,
  event: DocusealEvent,
): string {
  return [
    event.eventType,
    event.submissionId ?? "no-submission",
    event.submitterId ?? "no-submitter",
    payload.timestamp ?? "no-timestamp",
  ].join(":");
}

/** Signer statuses that mean "this person is done and won't sign later." */
const TERMINAL_STATUSES = new Set(["signed", "declined"]);

/**
 * Whether a document should flip to `completed`.
 *
 * A declined signer is terminal but not a completion — the document can never
 * be fully signed, so it must not be reported as completed.
 */
export function documentSigningOutcome(
  signerStatuses: readonly string[],
): "completed" | "declined" | "pending" {
  if (signerStatuses.length === 0) return "pending";
  if (signerStatuses.some((status) => status === "declined")) return "declined";
  if (signerStatuses.every((status) => TERMINAL_STATUSES.has(status))) return "completed";
  return "pending";
}
