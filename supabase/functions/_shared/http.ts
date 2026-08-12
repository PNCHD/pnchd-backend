/**
 * Webhook responses, named for what they tell the provider to do next rather
 * than for their status code. The code is a control signal: 2xx means "handled,
 * stop", non-2xx means "retry me later". Getting it backwards either causes a
 * multi-day retry storm on a payload that will never succeed, or silently drops
 * an event on a failure that would have succeeded on a second attempt.
 */

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Processed successfully. Provider stops. */
export function handled(detail?: Record<string, unknown>): Response {
  return json(200, { ok: true, ...detail });
}

/** Already processed (duplicate delivery). Provider stops. */
export function duplicate(eventId: string): Response {
  return json(200, { ok: true, skipped: "duplicate", eventId });
}

/**
 * Permanently unprocessable — malformed payload, unknown event type, or a
 * referenced record that does not exist. Returning 2xx is deliberate: a retry
 * would fail identically, and non-2xx here means the provider hammers the
 * endpoint for days over a payload we are never going to accept.
 */
export function rejected(reason: string, detail?: Record<string, unknown>): Response {
  console.warn(`Rejecting event permanently: ${reason}`, detail ?? {});
  return json(200, { ok: false, rejected: reason, ...detail });
}

/**
 * Transient failure — database unavailable, network blip. Non-2xx asks the
 * provider to redeliver.
 */
export function retryable(reason: string): Response {
  console.error(`Transient failure, requesting retry: ${reason}`);
  return json(500, { ok: false, error: reason });
}

/**
 * Signature verification failed. 400 rather than 2xx so a spoofing attempt or a
 * secret misconfiguration shows up as a failing endpoint in the provider's
 * dashboard instead of silently succeeding.
 */
export function badSignature(): Response {
  console.error("Webhook signature verification failed");
  return json(400, { ok: false, error: "invalid signature" });
}

export function methodNotAllowed(): Response {
  return json(405, { ok: false, error: "method not allowed" });
}
