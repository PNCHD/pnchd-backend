import { assertEquals } from "@std/assert";

import {
  diffModules,
  extractSubscriptionState,
  isModuleKey,
  type SubscriptionItemLike,
} from "./subscription-state.ts";

function moduleItem(moduleKey: string): SubscriptionItemLike {
  return { price: { metadata: { module_key: moduleKey } } };
}

Deno.test("extractSubscriptionState reads module keys from price metadata", () => {
  const state = extractSubscriptionState([
    moduleItem("scheduling"),
    moduleItem("document_signing"),
  ]);
  assertEquals(state.moduleKeys, ["scheduling", "document_signing"]);
  assertEquals(state.unknownModuleKeys, []);
});

Deno.test("extractSubscriptionState ignores items with no module metadata", () => {
  const state = extractSubscriptionState([
    { price: { metadata: { line_type: "base" } } },
    moduleItem("scheduling"),
  ]);
  assertEquals(state.moduleKeys, ["scheduling"]);
});

Deno.test("extractSubscriptionState surfaces unrecognized module keys", () => {
  const state = extractSubscriptionState([moduleItem("not_a_real_module")]);
  assertEquals(state.moduleKeys, []);
  assertEquals(state.unknownModuleKeys, ["not_a_real_module"]);
});

Deno.test("extractSubscriptionState reads seat count from the seats line", () => {
  const state = extractSubscriptionState([
    { price: { metadata: { line_type: "seats" } }, quantity: 3 },
    moduleItem("scheduling"),
  ]);
  assertEquals(state.seatCount, 3);
});

Deno.test("extractSubscriptionState defaults seat count to zero when absent", () => {
  assertEquals(extractSubscriptionState([moduleItem("scheduling")]).seatCount, 0);
});

Deno.test("extractSubscriptionState maps module keys to subscription item ids", () => {
  const state = extractSubscriptionState(
    [moduleItem("scheduling"), moduleItem("client_payments")],
    ["si_111", "si_222"],
  );
  assertEquals(state.itemIdByModule, {
    scheduling: "si_111",
    client_payments: "si_222",
  });
});

Deno.test("extractSubscriptionState deduplicates repeated module keys", () => {
  const state = extractSubscriptionState([
    moduleItem("scheduling"),
    moduleItem("scheduling"),
  ]);
  assertEquals(state.moduleKeys, ["scheduling"]);
});

Deno.test("extractSubscriptionState on an empty subscription yields empty state", () => {
  const state = extractSubscriptionState([]);
  assertEquals(state.moduleKeys, []);
  assertEquals(state.seatCount, 0);
});

Deno.test("isModuleKey accepts known keys and rejects others", () => {
  assertEquals(isModuleKey("fleet_tracking"), true);
  assertEquals(isModuleKey("fleet-tracking"), false);
  assertEquals(isModuleKey(""), false);
});

Deno.test("diffModules activates newly present modules", () => {
  assertEquals(
    diffModules(["scheduling", "messaging"], ["scheduling"]),
    { toActivate: ["messaging"], toDeactivate: [] },
  );
});

Deno.test("diffModules deactivates modules no longer in the subscription", () => {
  assertEquals(
    diffModules(["scheduling"], ["scheduling", "messaging"]),
    { toActivate: [], toDeactivate: ["messaging"] },
  );
});

Deno.test("diffModules is a no-op when state already matches", () => {
  assertEquals(
    diffModules(["scheduling", "messaging"], ["messaging", "scheduling"]),
    { toActivate: [], toDeactivate: [] },
  );
});

Deno.test("diffModules deactivates everything when the subscription empties", () => {
  assertEquals(
    diffModules([], ["scheduling", "messaging"]),
    { toActivate: [], toDeactivate: ["scheduling", "messaging"] },
  );
});
