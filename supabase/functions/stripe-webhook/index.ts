import Stripe from "stripe";

import { requireEnv } from "@shared/env.ts";
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

import { handleSubscriptionUpdated } from "./handlers/subscription-updated.ts";
import { handlePaymentIntentSucceeded } from "./handlers/payment-intent-succeeded.ts";

const stripe = new Stripe(requireEnv("STRIPE_SECRET_KEY"), {
  // Stripe's Node SDK defaults to a Node http client, which doesn't exist here.
  httpClient: Stripe.createFetchHttpClient(),
});
const webhookSecret = requireEnv("STRIPE_WEBHOOK_SECRET");
const admin = createAdminClient();

const HANDLED_EVENTS = new Set([
  "customer.subscription.updated",
  "payment_intent.succeeded",
]);

Deno.serve(async (req) => {
  if (req.method !== "POST") return methodNotAllowed();

  const signature = req.headers.get("stripe-signature");
  if (!signature) return badSignature();

  // Raw text, never a re-serialized object: the signature is an HMAC over the
  // exact bytes Stripe sent, and JSON.parse -> JSON.stringify changes them.
  const rawBody = await req.text();

  let event: Stripe.Event;
  try {
    // constructEventAsync, not constructEvent — the sync variant uses Node
    // crypto and fails on Deno's Web Crypto.
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      signature,
      webhookSecret,
    );
  } catch (error) {
    console.error("Stripe signature verification failed:", errorMessage(error));
    return badSignature();
  }

  if (!HANDLED_EVENTS.has(event.type)) {
    // Subscribing to fewer event types in the Stripe dashboard is better than
    // relying on this, but an unhandled type must not look like a failure.
    return handled({ ignored: event.type });
  }

  let claimed: boolean;
  try {
    claimed = await claimEvent(admin, "stripe", event.id, event.type);
  } catch (error) {
    return retryable(`idempotency claim failed: ${errorMessage(error)}`);
  }
  if (!claimed) return duplicate(event.id);

  try {
    const outcome = await route(event);

    if (outcome.status === "rejected") {
      // Permanently unprocessable. Mark completed, not failed — a retry would
      // reach the same conclusion, and leaving it failed invites re-claiming.
      await completeEvent(admin, "stripe", event.id);
      return rejected(outcome.reason, { eventId: event.id });
    }

    await completeEvent(admin, "stripe", event.id);
    return handled({ eventId: event.id, ...outcome.detail });
  } catch (error) {
    const message = errorMessage(error);
    await failEvent(admin, "stripe", event.id, message);
    return retryable(message);
  }
});

function route(event: Stripe.Event) {
  switch (event.type) {
    case "customer.subscription.updated":
      return handleSubscriptionUpdated(
        admin,
        event.data.object as Stripe.Subscription,
      );
    case "payment_intent.succeeded":
      return handlePaymentIntentSucceeded(
        admin,
        event.data.object as Stripe.PaymentIntent,
      );
    default:
      return Promise.resolve(
        { status: "rejected", reason: `unrouted event type ${event.type}` } as const,
      );
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
