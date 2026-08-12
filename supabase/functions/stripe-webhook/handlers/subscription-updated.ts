import type { SupabaseClient } from "@supabase/supabase-js";
import type Stripe from "stripe";

import {
  diffModules,
  extractSubscriptionState,
} from "@shared/subscription-state.ts";

export type HandlerOutcome =
  | { status: "handled"; detail?: Record<string, unknown> }
  | { status: "rejected"; reason: string };

/**
 * customer.subscription.updated — syncs module_subscriptions and seat_count
 * (ARCHITECTURE.md Section 8.2).
 *
 * Also fires on module removal at period end (Section 2.5): Stripe drops the
 * item from the subscription on renewal, the item disappears from the payload,
 * and the reconcile below deactivates it.
 */
export async function handleSubscriptionUpdated(
  admin: SupabaseClient,
  subscription: Stripe.Subscription,
): Promise<HandlerOutcome> {
  const customerId = typeof subscription.customer === "string"
    ? subscription.customer
    : subscription.customer?.id;

  if (!customerId) {
    return { status: "rejected", reason: "subscription has no customer id" };
  }

  const { data: org, error: orgError } = await admin
    .from("organizations")
    .select("id, founding_member, seat_count")
    .eq("stripe_customer_id", customerId)
    .maybeSingle();

  if (orgError) throw new Error(`org lookup failed: ${orgError.message}`);
  if (!org) {
    // Not retryable: a customer we've never seen won't appear on redelivery.
    return {
      status: "rejected",
      reason: `no organization for stripe_customer_id ${customerId}`,
    };
  }

  const items = subscription.items?.data ?? [];
  const state = extractSubscriptionState(
    items,
    items.map((item) => item.id),
  );

  if (state.unknownModuleKeys.length > 0) {
    console.warn(
      `Subscription ${subscription.id} carries unrecognized module_key metadata`,
      state.unknownModuleKeys,
    );
  }

  await syncSeatCount(admin, org.id, org.seat_count, state.seatCount);

  // Founding member guard — Section 2.3, Layer 3.
  //
  // This is load-bearing, not belt-and-braces. Founding members are billed a
  // flat rate with no per-module subscription items, so the reconcile below
  // would compute an empty desired set and deactivate every module they have,
  // silently stripping the access they were promised for life. Skip module
  // reconciliation for them entirely; their modules are granted by the
  // founding-member terms, not by subscription items.
  if (org.founding_member) {
    if (state.moduleKeys.length > 0) {
      console.warn(
        `Founding member org ${org.id} has per-module subscription items ` +
          `(${state.moduleKeys.join(", ")}) — unexpected under a flat rate. ` +
          `Module state left untouched; investigate the subscription.`,
      );
    }
    return {
      status: "handled",
      detail: { organizationId: org.id, foundingMember: true, modulesSkipped: true },
    };
  }

  const { data: activeRows, error: activeError } = await admin
    .from("module_subscriptions")
    .select("module_key")
    .eq("organization_id", org.id)
    .eq("is_active", true);

  if (activeError) {
    throw new Error(`active module lookup failed: ${activeError.message}`);
  }

  const currentlyActive = (activeRows ?? []).map((row) => row.module_key as string);
  const { toActivate, toDeactivate } = diffModules(state.moduleKeys, currentlyActive);

  // Deactivate first. toActivate was computed against currently-active rows, so
  // after this there is no active row for any key being inserted — which keeps
  // the partial unique index on (organization_id, module_key) where is_active
  // satisfied without needing an upsert against a partial index.
  if (toDeactivate.length > 0) {
    const { error } = await admin
      .from("module_subscriptions")
      .update({ is_active: false, deactivated_at: new Date().toISOString() })
      .eq("organization_id", org.id)
      .eq("is_active", true)
      .in("module_key", toDeactivate);

    if (error) throw new Error(`module deactivation failed: ${error.message}`);
  }

  if (toActivate.length > 0) {
    const { error } = await admin.from("module_subscriptions").insert(
      toActivate.map((moduleKey) => ({
        organization_id: org.id,
        module_key: moduleKey,
        stripe_subscription_item_id: state.itemIdByModule[moduleKey] ?? null,
        is_active: true,
      })),
    );

    if (error) throw new Error(`module activation failed: ${error.message}`);
  }

  return {
    status: "handled",
    detail: {
      organizationId: org.id,
      activated: toActivate,
      deactivated: toDeactivate,
      seatCount: state.seatCount,
    },
  };
}

async function syncSeatCount(
  admin: SupabaseClient,
  organizationId: string,
  current: number | null,
  next: number,
): Promise<void> {
  if (current === next) return;

  const { error } = await admin
    .from("organizations")
    .update({ seat_count: next })
    .eq("id", organizationId);

  if (error) throw new Error(`seat_count sync failed: ${error.message}`);
}
