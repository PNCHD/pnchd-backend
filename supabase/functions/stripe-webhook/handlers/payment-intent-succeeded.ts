import type { SupabaseClient } from "@supabase/supabase-js";
import type Stripe from "stripe";

import type { HandlerOutcome } from "./subscription-updated.ts";

/**
 * payment_intent.succeeded — marks the invoice paid (ARCHITECTURE.md Section
 * 8.3, step 7) and raises the in-app notification (Section 8.4, step 4).
 *
 * `paid` is reachable only from here. The client-write trigger on invoices
 * (migration 006) lets a client move sent -> approved and nothing further, so
 * payment state can only ever be set by this trusted path.
 */
export async function handlePaymentIntentSucceeded(
  admin: SupabaseClient,
  paymentIntent: Stripe.PaymentIntent,
): Promise<HandlerOutcome> {
  const { data: invoice, error: lookupError } = await admin
    .from("invoices")
    .select("id, organization_id, client_id, title, status, total_cents")
    .eq("stripe_payment_intent_id", paymentIntent.id)
    .maybeSingle();

  if (lookupError) throw new Error(`invoice lookup failed: ${lookupError.message}`);
  if (!invoice) {
    // Not every PaymentIntent belongs to an invoice, and one we've never
    // recorded won't materialize on redelivery.
    return {
      status: "rejected",
      reason: `no invoice for payment_intent ${paymentIntent.id}`,
    };
  }

  if (invoice.status === "paid") {
    return { status: "handled", detail: { invoiceId: invoice.id, alreadyPaid: true } };
  }

  if (invoice.status === "voided" || invoice.status === "refunded") {
    // Real money arrived against an invoice that shouldn't have accepted it.
    // Don't overwrite the terminal state — flag it for a human.
    console.error(
      `PaymentIntent ${paymentIntent.id} succeeded against ${invoice.status} ` +
        `invoice ${invoice.id} — needs manual reconciliation`,
    );
    return {
      status: "rejected",
      reason: `invoice ${invoice.id} is ${invoice.status}`,
    };
  }

  const { error: updateError } = await admin
    .from("invoices")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("id", invoice.id)
    .neq("status", "paid");

  if (updateError) throw new Error(`invoice update failed: ${updateError.message}`);

  await notifyInvoicePaid(admin, invoice);

  return { status: "handled", detail: { invoiceId: invoice.id, status: "paid" } };
}

interface InvoiceRow {
  id: string;
  organization_id: string;
  client_id: string | null;
  title: string | null;
  total_cents: number | null;
}

/**
 * Notification failure must not fail the webhook — the payment is already
 * recorded, and a non-2xx here would make Stripe redeliver an event whose
 * financial work is done.
 */
async function notifyInvoicePaid(
  admin: SupabaseClient,
  invoice: InvoiceRow,
): Promise<void> {
  if (!invoice.client_id) return;

  const { error } = await admin.from("notifications").insert({
    organization_id: invoice.organization_id,
    recipient_id: invoice.client_id,
    title: "Payment received",
    body: `Your payment for "${invoice.title ?? "invoice"}" was received.`,
    type: "invoice_paid",
    reference_type: "invoice",
    reference_id: invoice.id,
  });

  if (error) {
    console.error(`notification insert failed for invoice ${invoice.id}: ${error.message}`);
  }
}
