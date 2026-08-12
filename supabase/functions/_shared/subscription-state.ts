/**
 * Pure logic for turning a Stripe subscription into the module/seat state the
 * database should converge to. Kept free of Stripe SDK and Supabase types so it
 * can be unit tested directly.
 */

/** ARCHITECTURE.md Section 2.2. Mirrors the module_subscriptions check constraint. */
export const MODULE_KEYS = [
  "scheduling",
  "document_signing",
  "proposals_invoicing",
  "client_payments",
  "fleet_tracking",
  "messaging",
  "budget_tracking",
  "file_storage",
  "multi_contractor",
  "client_portal",
] as const;

export type ModuleKey = (typeof MODULE_KEYS)[number];

const MODULE_KEY_SET: ReadonlySet<string> = new Set(MODULE_KEYS);

export function isModuleKey(value: string): value is ModuleKey {
  return MODULE_KEY_SET.has(value);
}

/**
 * The shape we need off a Stripe subscription item. Stripe metadata is the join
 * key between a Price and a PNCHD module: each module's Price carries
 * `metadata.module_key`, and the additional-seats Price carries
 * `metadata.line_type = "seats"`.
 */
export interface SubscriptionItemLike {
  quantity?: number | null;
  price?: {
    id?: string;
    metadata?: Record<string, string> | null;
  } | null;
}

export interface SubscriptionState {
  moduleKeys: ModuleKey[];
  seatCount: number;
  /** Price IDs carrying a module_key we don't recognize — surfaced, not silently dropped. */
  unknownModuleKeys: string[];
  /** module_key -> subscription item id, for storing stripe_subscription_item_id. */
  itemIdByModule: Record<string, string>;
}

/**
 * Reads the desired state off the subscription's items.
 *
 * Deliberately derived from the full item list rather than from the event's
 * delta: Stripe does not guarantee delivery order (Section 8.5), so reconciling
 * toward a complete snapshot is the only version that converges correctly when
 * events arrive out of order.
 */
export function extractSubscriptionState(
  items: readonly SubscriptionItemLike[],
  itemIds: readonly (string | undefined)[] = [],
): SubscriptionState {
  const moduleKeys: ModuleKey[] = [];
  const unknownModuleKeys: string[] = [];
  const itemIdByModule: Record<string, string> = {};
  let seatCount = 0;

  items.forEach((item, index) => {
    const metadata = item.price?.metadata ?? {};
    const moduleKey = metadata.module_key;
    const itemId = itemIds[index];

    if (moduleKey) {
      if (isModuleKey(moduleKey)) {
        if (!moduleKeys.includes(moduleKey)) moduleKeys.push(moduleKey);
        if (itemId) itemIdByModule[moduleKey] = itemId;
      } else {
        unknownModuleKeys.push(moduleKey);
      }
    }

    if (metadata.line_type === "seats") {
      seatCount = item.quantity ?? 0;
    }
  });

  return { moduleKeys, seatCount, unknownModuleKeys, itemIdByModule };
}

export interface ModuleDiff {
  toActivate: string[];
  toDeactivate: string[];
}

/** What has to change for currently-active modules to match the desired set. */
export function diffModules(
  desired: readonly string[],
  currentlyActive: readonly string[],
): ModuleDiff {
  const desiredSet = new Set(desired);
  const activeSet = new Set(currentlyActive);

  return {
    toActivate: desired.filter((key) => !activeSet.has(key)),
    toDeactivate: currentlyActive.filter((key) => !desiredSet.has(key)),
  };
}
