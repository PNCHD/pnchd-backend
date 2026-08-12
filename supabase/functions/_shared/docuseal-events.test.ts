import { assertEquals, assertNotEquals } from "@std/assert";

import {
  docusealEventKey,
  documentSigningOutcome,
  parseDocusealEvent,
} from "./docuseal-events.ts";

Deno.test("parseDocusealEvent extracts submitter and submission ids as strings", () => {
  const event = parseDocusealEvent({
    event_type: "form.completed",
    data: { id: 42, submission_id: 7, email: "client@example.com" },
  });
  assertEquals(event?.eventType, "form.completed");
  assertEquals(event?.submitterId, "42");
  assertEquals(event?.submissionId, "7");
  assertEquals(event?.email, "client@example.com");
});

Deno.test("parseDocusealEvent falls back to nested submission id", () => {
  const event = parseDocusealEvent({
    event_type: "form.completed",
    data: { id: 1, submission: { id: 99 } },
  });
  assertEquals(event?.submissionId, "99");
});

Deno.test("parseDocusealEvent returns null without an event type", () => {
  assertEquals(parseDocusealEvent({ data: { id: 1 } }), null);
});

Deno.test("docusealEventKey is stable for a redelivery of the same event", () => {
  const payload = {
    event_type: "form.completed",
    timestamp: "2026-08-11T19:00:00Z",
    data: { id: 42, submission_id: 7 },
  };
  const key = docusealEventKey(payload, parseDocusealEvent(payload)!);
  assertEquals(key, docusealEventKey(payload, parseDocusealEvent(payload)!));
});

Deno.test("docusealEventKey differs across event types for the same submitter", () => {
  const base = { timestamp: "2026-08-11T19:00:00Z", data: { id: 42, submission_id: 7 } };
  const viewed = { ...base, event_type: "form.viewed" };
  const completed = { ...base, event_type: "form.completed" };
  assertNotEquals(
    docusealEventKey(viewed, parseDocusealEvent(viewed)!),
    docusealEventKey(completed, parseDocusealEvent(completed)!),
  );
});

Deno.test("documentSigningOutcome is pending while any signer is outstanding", () => {
  assertEquals(documentSigningOutcome(["signed", "pending"]), "pending");
  assertEquals(documentSigningOutcome(["sent", "opened"]), "pending");
});

Deno.test("documentSigningOutcome completes when every signer has signed", () => {
  assertEquals(documentSigningOutcome(["signed", "signed"]), "completed");
  assertEquals(documentSigningOutcome(["signed"]), "completed");
});

Deno.test("documentSigningOutcome reports declined even alongside signatures", () => {
  // A declined signer is terminal but the document can never complete — it must
  // not be reported as completed just because every signer is in a final state.
  assertEquals(documentSigningOutcome(["signed", "declined"]), "declined");
  assertEquals(documentSigningOutcome(["declined", "pending"]), "declined");
});

Deno.test("documentSigningOutcome treats a document with no signers as pending", () => {
  assertEquals(documentSigningOutcome([]), "pending");
});
