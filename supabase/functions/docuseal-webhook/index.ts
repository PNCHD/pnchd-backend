import type { SupabaseClient } from "@supabase/supabase-js";

import {
  docusealEventKey,
  documentSigningOutcome,
  parseDocusealEvent,
  type DocusealEvent,
  type DocusealPayload,
} from "@shared/docuseal-events.ts";
import { requireEnv } from "@shared/env.ts";
import { verifyHmacSignature } from "@shared/hmac.ts";
import {
  badSignature,
  duplicate,
  handled,
  methodNotAllowed,
  rejected,
  retryable,
} from "@shared/http.ts";
import { claimEvent, completeEvent, failEvent } from "@shared/idempotency.ts";
import { createAdminClient } from "@shared/supabase-admin.ts";

const webhookSecret = requireEnv("DOCUSEAL_WEBHOOK_SECRET");
const admin = createAdminClient();

/** Docuseal fires several event types; only signer completion changes state here. */
const SIGNER_COMPLETED_EVENTS = new Set(["form.completed", "form.declined"]);

Deno.serve(async (req) => {
  if (req.method !== "POST") return methodNotAllowed();

  const rawBody = await req.text();
  const signature = req.headers.get("x-docuseal-signature") ??
    req.headers.get("x-signature");

  if (!await verifyHmacSignature(webhookSecret, rawBody, signature)) {
    return badSignature();
  }

  let payload: DocusealPayload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return rejected("payload is not valid JSON");
  }

  const event = parseDocusealEvent(payload);
  if (!event) return rejected("payload has no event_type");

  if (!SIGNER_COMPLETED_EVENTS.has(event.eventType)) {
    return handled({ ignored: event.eventType });
  }

  const eventKey = docusealEventKey(payload, event);

  let claimed: boolean;
  try {
    claimed = await claimEvent(admin, "docuseal", eventKey, event.eventType);
  } catch (error) {
    return retryable(`idempotency claim failed: ${errorMessage(error)}`);
  }
  if (!claimed) return duplicate(eventKey);

  try {
    const outcome = await applySignerCompletion(admin, event, req);

    await completeEvent(admin, "docuseal", eventKey);
    return outcome.status === "rejected"
      ? rejected(outcome.reason, { eventKey })
      : handled({ eventKey, ...outcome.detail });
  } catch (error) {
    const message = errorMessage(error);
    await failEvent(admin, "docuseal", eventKey, message);
    return retryable(message);
  }
});

type Outcome =
  | { status: "handled"; detail?: Record<string, unknown> }
  | { status: "rejected"; reason: string };

async function applySignerCompletion(
  admin: SupabaseClient,
  event: DocusealEvent,
  req: Request,
): Promise<Outcome> {
  if (!event.submitterId) return { status: "rejected", reason: "event has no submitter id" };

  const { data: signer, error: signerError } = await admin
    .from("document_signers")
    .select("id, document_id, organization_id, profile_id, signer_name, status")
    .eq("docuseal_submitter_id", event.submitterId)
    .maybeSingle();

  if (signerError) throw new Error(`signer lookup failed: ${signerError.message}`);
  if (!signer) {
    return {
      status: "rejected",
      reason: `no document_signer for docuseal_submitter_id ${event.submitterId}`,
    };
  }

  const declined = event.eventType === "form.declined";

  if (signer.status === "signed" || signer.status === "declined") {
    return { status: "handled", detail: { signerId: signer.id, alreadyTerminal: true } };
  }

  const { error: updateError } = await admin
    .from("document_signers")
    .update({
      status: declined ? "declined" : "signed",
      signed_at: declined ? null : (event.completedAt ?? new Date().toISOString()),
      signing_ip: clientIp(req),
    })
    .eq("id", signer.id);

  if (updateError) throw new Error(`signer update failed: ${updateError.message}`);

  const documentStatus = await reconcileDocumentStatus(admin, signer.document_id);

  if (documentStatus === "completed") {
    await notifyDocumentCompleted(admin, signer);
  }

  return {
    status: "handled",
    detail: { signerId: signer.id, documentId: signer.document_id, documentStatus },
  };
}

/**
 * Recomputes document status from all its signers rather than from this one
 * event, so out-of-order deliveries converge to the same answer.
 */
async function reconcileDocumentStatus(
  admin: SupabaseClient,
  documentId: string,
): Promise<string> {
  const { data: signers, error } = await admin
    .from("document_signers")
    .select("status")
    .eq("document_id", documentId);

  if (error) throw new Error(`signer roll-up failed: ${error.message}`);

  const outcome = documentSigningOutcome(
    (signers ?? []).map((row) => row.status as string),
  );
  if (outcome === "pending") return "pending";

  // `documents.status` has no `declined` value (migration 008); a declined
  // document is voided. Flagged in ARCHITECTURE.md Section 5.2 as a gap if a
  // distinct declined state turns out to matter.
  const nextStatus = outcome === "completed" ? "completed" : "voided";

  const { error: updateError } = await admin
    .from("documents")
    .update({ status: nextStatus })
    .eq("id", documentId)
    .neq("status", nextStatus);

  if (updateError) throw new Error(`document status update failed: ${updateError.message}`);
  return nextStatus;
}

interface SignerRow {
  document_id: string;
  organization_id: string;
  profile_id: string | null;
  signer_name: string | null;
}

async function notifyDocumentCompleted(
  admin: SupabaseClient,
  signer: SignerRow,
): Promise<void> {
  if (!signer.profile_id) return;

  const { error } = await admin.from("notifications").insert({
    organization_id: signer.organization_id,
    recipient_id: signer.profile_id,
    title: "Document signed",
    body: "All signatures are complete on your document.",
    type: "document_signed",
    reference_type: "document",
    reference_id: signer.document_id,
  });

  if (error) console.error(`notification insert failed: ${error.message}`);
}

function clientIp(req: Request): string | null {
  const forwarded = req.headers.get("x-forwarded-for");
  return forwarded ? forwarded.split(",")[0].trim() : null;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
