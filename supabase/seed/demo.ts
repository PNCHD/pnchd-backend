import { createClient } from "npm:@supabase/supabase-js@2.58.0";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const REDIRECT = Deno.env.get("REDIRECT_TO") ?? "http://localhost:5183/dashboard";
const EMAIL = "demo@pnchd.test";

const admin = createClient(URL_, SR, { auth: { persistSession: false } });

// Idempotent: wipe any previous demo account so re-running is safe.
// Order matters — every profile in the org must go before the org itself
// (profiles.organization_id references it), and the org before its owner
// (organizations.owner_id references auth.users).
const { data: existing } = await admin.auth.admin.listUsers();
const demoUsers = existing.users.filter(
  (u) => u.email === EMAIL || u.email === "client@pnchd.test",
);

if (demoUsers.length > 0) {
  const ids = demoUsers.map((u) => u.id);
  // Orgs reachable two ways: via a profile, and via owner_id. A previously
  // failed run can leave an org whose profiles are gone but whose owner_id
  // still pins the auth user, which then refuses to delete.
  const { data: profiles } = await admin
    .from("profiles").select("organization_id").in("id", ids);
  const { data: owned } = await admin
    .from("organizations").select("id").in("owner_id", ids);
  const orgIds = [
    ...new Set([
      ...(profiles ?? []).map((p) => p.organization_id),
      ...(owned ?? []).map((o) => o.id),
    ].filter(Boolean)),
  ] as string[];

  for (const table of [
    "line_items", "proposals", "invoices", "projects",
    "module_subscriptions", "client_feature_toggles", "notifications",
  ]) {
    if (orgIds.length > 0) {
      await admin.from(table).delete().in("organization_id", orgIds);
    }
  }
  await admin.from("profiles").delete().in("id", ids);
  if (orgIds.length > 0) {
    // Any other org member would re-block the org delete.
    await admin.from("profiles").delete().in("organization_id", orgIds);
    const { error } = await admin.from("organizations").delete().in("id", orgIds);
    if (error) throw new Error(`could not delete orgs: ${error.message}`);
  }
  for (const id of ids) {
    const { error } = await admin.auth.admin.deleteUser(id);
    if (error) throw new Error(`could not delete prior user ${id}: ${error.message}`);
  }
}

const { data: created, error: userError } = await admin.auth.admin.createUser({
  email: EMAIL,
  email_confirm: true,
  user_metadata: { role: "owner", full_name: "Demo Contractor" },
});
if (userError) throw userError;
const userId = created.user!.id;

const { data: org, error: orgError } = await admin
  .from("organizations")
  .insert({ name: "Ridgeline Construction", owner_id: userId })
  .select("id").single();
if (orgError) throw orgError;

await admin.from("profiles")
  .update({ organization_id: org.id, role: "owner" }).eq("id", userId);

// A couple of modules so the nav isn't bare.
await admin.from("module_subscriptions").insert([
  { organization_id: org.id, module_key: "scheduling", is_active: true },
  { organization_id: org.id, module_key: "proposals_invoicing", is_active: true },
  { organization_id: org.id, module_key: "document_signing", is_active: true },
]);

const projects = [
  ["Kitchen remodel — Whitmore residence", "2841 Larkspur Ln, Boulder, CO", "active"],
  ["Deck rebuild — Alvarez", "119 Cedar Ct, Longmont, CO", "active"],
  ["Basement finish — Okafor", "77 Sunview Dr, Erie, CO", "on_hold"],
  ["Bathroom addition — Beckett", "5 Mill Race Rd, Niwot, CO", "draft"],
  ["Garage conversion — Tran", "412 Quail Run, Lafayette, CO", "completed"],
  ["Roof replacement — Ferris", "88 Alpine Way, Superior, CO", "archived"],
];

await admin.from("projects").insert(
  projects.map(([title, address, status]) => ({
    organization_id: org.id,
    created_by: userId,
    title,
    address,
    status,
  })),
);

// A client to bill, plus proposals and invoices with real line items.
const { data: clientUser } = await admin.auth.admin.createUser({
  email: "client@pnchd.test",
  email_confirm: true,
  user_metadata: { role: "client", full_name: "Dana Whitmore" },
});
await admin.from("profiles")
  .update({ organization_id: org.id, role: "client" }).eq("id", clientUser.user!.id);

async function billing(
  table: "proposals" | "invoices",
  title: string,
  status: string,
  lines: [string, number, number][],
  extra: Record<string, unknown> = {},
) {
  const items = lines.map(([description, quantity, unitPriceCents], i) => ({
    description,
    quantity,
    unit_price_cents: unitPriceCents,
    total_cents: Math.round(quantity * unitPriceCents),
    sort_order: i,
  }));
  const subtotal = items.reduce((sum, i) => sum + i.total_cents, 0);
  const taxRate = table === "proposals" ? 8.25 : null;
  const tax = taxRate ? Math.round((subtotal * taxRate) / 100) : null;

  const { data: parent } = await admin.from(table).insert({
    organization_id: org.id,
    client_id: clientUser.user!.id,
    title,
    status,
    subtotal_cents: subtotal,
    total_cents: subtotal + (tax ?? 0),
    ...(table === "proposals" ? { tax_rate_percent: taxRate, tax_cents: tax } : { tax_cents: tax }),
    ...extra,
  }).select("id").single();

  await admin.from("line_items").insert(
    items.map((i) => ({
      ...i,
      organization_id: org.id,
      parent_type: table === "proposals" ? "proposal" : "invoice",
      parent_id: parent!.id,
    })),
  );
}

await billing("proposals", "Kitchen remodel — full scope", "draft", [
  ["Demolition and haul-away", 1, 185000],
  ["Cabinetry — shaker, painted", 24, 47500],
  ["Quartz countertops", 38.5, 8900],
  ["Electrical rough-in", 16, 11500],
]);
await billing("proposals", "Deck rebuild — cedar", "sent", [
  ["Cedar decking", 320, 1250],
  ["Framing labor", 28, 9500],
  ["Railing and hardware", 1, 142000],
]);
await billing("proposals", "Basement finish — phase 1", "approved", [
  ["Framing and insulation", 1, 875000],
  ["Drywall", 1, 412000],
], { approved_at: new Date().toISOString() });

await billing("invoices", "Deck rebuild — deposit", "paid", [
  ["50% deposit", 1, 289000],
], { paid_at: new Date().toISOString() });
await billing("invoices", "Kitchen remodel — progress billing 1", "sent", [
  ["Demolition complete", 1, 185000],
  ["Cabinetry deposit", 1, 570000],
]);
await billing("invoices", "Bathroom addition — materials", "draft", [
  ["Tile and fixtures", 1, 78400],
  ["Plumbing rough-in", 12, 11500],
]);

const { data: link, error: linkError } = await admin.auth.admin.generateLink({
  type: "magiclink",
  email: EMAIL,
  options: { redirectTo: REDIRECT },
});
if (linkError) throw linkError;

console.log("\nSeeded 'Ridgeline Construction': 6 projects, 3 proposals, 3 invoices.\n");
console.log("Sign-in link (opens straight into the app):\n");
console.log(link.properties.action_link);
console.log();
