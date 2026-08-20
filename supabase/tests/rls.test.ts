import { assert, assertEquals } from "@std/assert";

import {
  admin,
  readable,
  seed,
  seedUnattachedUser,
  type Fixture,
} from "./fixtures.ts";

/**
 * Access-control assertions run as real signed-in users. See fixtures.ts for
 * why service_role checks are not a substitute.
 *
 * Run: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... SUPABASE_ANON_KEY=... \
 *        deno task rls
 */

const fixture: Fixture = await seed();

async function withCleanup(fn: () => Promise<void>) {
  try {
    await fn();
  } finally {
    // no-op per test; teardown runs once at the end
  }
}

Deno.test("regression: every role can read its own profile", async () => {
  // 42P17 here means the profiles policy recurses through itself, which takes
  // down every table in the project. This is the canary.
  for (const [label, user] of Object.entries(fixture.orgA.users)) {
    const { data, error } = await user.client
      .from("profiles")
      .select("id, role, organization_id")
      .eq("id", user.id)
      .maybeSingle();

    assertEquals(error?.code ?? null, null, `${label}: ${error?.message ?? ""}`);
    assertEquals(data?.id, user.id, `${label} could not read own profile`);
  }
});

Deno.test("regression: authenticated reads are not blocked by missing GRANTs", async () => {
  // 42501 means the table privilege is missing, which RLS never even gets to.
  const { errorCode } = await readable(fixture.orgA.users.owner.client, "projects");
  assert(errorCode !== "42501", "owner lacks SELECT privilege on projects");
});

Deno.test("org isolation: a contractor sees only their own org's projects", async () => {
  await withCleanup(async () => {
    const { data: projectA } = await admin
      .from("projects")
      .insert({
        organization_id: fixture.orgA.id,
        title: "Org A project",
        created_by: fixture.orgA.users.owner.id,
      })
      .select("id")
      .single();

    await admin.from("projects").insert({
      organization_id: fixture.orgB.id,
      title: "Org B project",
      created_by: fixture.orgB.users.owner.id,
    });

    const { data: visible } = await fixture.orgA.users.owner.client
      .from("projects")
      .select("id, organization_id");

    assertEquals(visible?.length, 1, "owner should see exactly their own org's project");
    assertEquals(visible?.[0].id, projectA!.id);
    assertEquals(visible?.[0].organization_id, fixture.orgA.id);
  });
});

Deno.test("org isolation: a contractor cannot read another org's profiles", async () => {
  const { data } = await fixture.orgA.users.owner.client
    .from("profiles")
    .select("id, organization_id");

  const foreign = (data ?? []).filter(
    (row) => row.organization_id !== fixture.orgA.id,
  );
  assertEquals(foreign.length, 0, "profiles leaked across organizations");
});

Deno.test("clients see only their own invoices, not the whole org's", async () => {
  const { data: mine } = await admin
    .from("invoices")
    .insert({
      organization_id: fixture.orgA.id,
      client_id: fixture.orgA.users.client.id,
      title: "Client's invoice",
      subtotal_cents: 1000,
      total_cents: 1000,
      status: "sent",
    })
    .select("id")
    .single();

  // Same org, different client — must not be visible.
  await admin.from("invoices").insert({
    organization_id: fixture.orgA.id,
    client_id: fixture.orgA.users.owner.id,
    title: "Someone else's invoice",
    subtotal_cents: 5000,
    total_cents: 5000,
    status: "sent",
  });

  const { data: visible } = await fixture.orgA.users.client.client
    .from("invoices")
    .select("id");

  assertEquals(visible?.length, 1, "client saw invoices that are not theirs");
  assertEquals(visible?.[0].id, mine!.id);
});

Deno.test("drivers have no access to vehicles", async () => {
  await admin.from("vehicles").insert({
    organization_id: fixture.orgA.id,
    name: "Truck 1",
  });

  const { count } = await readable(fixture.orgA.users.driver.client, "vehicles");
  assertEquals(count, 0, "driver could read vehicles (Section 7.2 says no access)");
});

Deno.test("module gating: vehicle_locations is unreadable without fleet_tracking", async () => {
  const { count: before } = await readable(
    fixture.orgA.users.owner.client,
    "vehicle_locations",
  );
  assertEquals(before, 0, "vehicle_locations readable without the fleet module");

  await admin.from("module_subscriptions").insert({
    organization_id: fixture.orgA.id,
    module_key: "fleet_tracking",
    is_active: true,
  });

  const { data: vehicle } = await admin
    .from("vehicles")
    .insert({ organization_id: fixture.orgA.id, name: "Truck 2" })
    .select("id")
    .single();

  await admin.from("vehicle_locations").insert({
    vehicle_id: vehicle!.id,
    organization_id: fixture.orgA.id,
    driver_id: fixture.orgA.users.driver.id,
    latitude: 39.7,
    longitude: -104.9,
  });

  const { count: after } = await readable(
    fixture.orgA.users.owner.client,
    "vehicle_locations",
  );
  assertEquals(after, 1, "fleet module active but locations still unreadable");
});

Deno.test("client_feature_toggles hard block on invoice approval", async () => {
  const { data: invoice } = await admin
    .from("invoices")
    .insert({
      organization_id: fixture.orgA.id,
      client_id: fixture.orgA.users.client.id,
      title: "Toggle test",
      subtotal_cents: 2000,
      total_cents: 2000,
      status: "sent",
    })
    .select("id")
    .single();

  const approve = () =>
    fixture.orgA.users.client.client
      .from("invoices")
      .update({ status: "approved" })
      .eq("id", invoice!.id)
      .select("id");

  // Toggle absent entirely — is_client_feature_enabled defaults to false.
  const denied = await approve();
  assertEquals(denied.data?.length ?? 0, 0, "approved with no toggle row present");

  await admin.from("client_feature_toggles").insert({
    organization_id: fixture.orgA.id,
    feature_key: "client_payments",
    is_enabled: true,
  });

  const allowed = await approve();
  assertEquals(allowed.data?.length, 1, "toggle on but client still blocked");

  // Flip off mid-flow: the hard-block decision means an already-sent invoice
  // becomes unapprovable, with no grandfathering.
  await admin
    .from("invoices")
    .update({ status: "sent" })
    .eq("id", invoice!.id);
  await admin
    .from("client_feature_toggles")
    .update({ is_enabled: false })
    .eq("organization_id", fixture.orgA.id)
    .eq("feature_key", "client_payments");

  const blocked = await approve();
  assertEquals(blocked.data?.length ?? 0, 0, "toggle off but client could still approve");

  const { data: final } = await admin
    .from("invoices")
    .select("status")
    .eq("id", invoice!.id)
    .single();
  assertEquals(final?.status, "sent", "write was not actually denied");
});

Deno.test("platform_admin can read across organizations", async () => {
  const { data } = await fixture.orgA.users.admin.client
    .from("organizations")
    .select("id");

  const ids = (data ?? []).map((row) => row.id);
  assert(ids.includes(fixture.orgA.id), "admin cannot see own org");
  assert(ids.includes(fixture.orgB.id), "admin bypass does not cross orgs");
});

Deno.test("webhook_events is unreachable by any authenticated role", async () => {
  for (const [label, user] of Object.entries(fixture.orgA.users)) {
    const { count, errorCode } = await readable(user.client, "webhook_events");
    assert(
      count === 0 || errorCode !== null,
      `${label} could read webhook_events`,
    );
  }
});

Deno.test("signup: a new user starts unattached, then can create their own org", async () => {
  const { user, cleanup } = await seedUnattachedUser(fixture.runId);

  try {
    // The handle_new_user trigger creates the profile with organization_id NULL.
    // The web app keys its org-setup routing off exactly this.
    const { data: initial, error: readError } = await user.client
      .from("profiles")
      .select("id, role, organization_id")
      .eq("id", user.id)
      .maybeSingle();

    assertEquals(readError?.code ?? null, null, readError?.message ?? "");
    assertEquals(initial?.organization_id, null, "new profile should have no org");
    assertEquals(initial?.role, "owner");

    // Step 1 of OrganizationRepository.createForOwner — the insert policy on
    // organizations requires owner_id = auth.uid(), so this is the only shape
    // that works.
    const { data: org, error: orgError } = await user.client
      .from("organizations")
      .insert({ name: "Signup Test Co", owner_id: user.id })
      .select("id")
      .single();

    assertEquals(orgError?.code ?? null, null, orgError?.message ?? "");
    assert(org?.id, "org was not created");

    // Step 2 — attach the profile.
    const { error: attachError } = await user.client
      .from("profiles")
      .update({ organization_id: org!.id })
      .eq("id", user.id);

    assertEquals(attachError?.code ?? null, null, attachError?.message ?? "");

    const { data: attached } = await user.client
      .from("profiles")
      .select("organization_id")
      .eq("id", user.id)
      .maybeSingle();
    assertEquals(attached?.organization_id, org!.id, "profile not attached to org");

    // And the new org is isolated from everyone else's data.
    const { data: visibleOrgs } = await user.client.from("organizations").select("id");
    assertEquals(visibleOrgs?.length, 1, "new owner can see other organizations");
    assertEquals(visibleOrgs?.[0].id, org!.id);
  } finally {
    await cleanup();
  }
});

Deno.test("signup: a user cannot create an organization owned by someone else", async () => {
  const { user, cleanup } = await seedUnattachedUser(`${fixture.runId}b`);

  try {
    const { error } = await user.client
      .from("organizations")
      .insert({ name: "Hijack Co", owner_id: fixture.orgA.users.owner.id })
      .select("id")
      .single();

    assert(error !== null, "was able to create an org owned by another user");
  } finally {
    await cleanup();
  }
});

Deno.test("projects: a contractor can create one in their own org", async () => {
  const owner = fixture.orgA.users.owner;

  const { data, error } = await owner.client
    .from("projects")
    .insert({
      organization_id: fixture.orgA.id,
      created_by: owner.id,
      title: "Created by owner",
      status: "draft",
    })
    .select("id, organization_id, status")
    .single();

  assertEquals(error?.code ?? null, null, error?.message ?? "");
  assertEquals(data?.organization_id, fixture.orgA.id);
  assertEquals(data?.status, "draft");
});

Deno.test("projects: a contractor cannot create one in another org", async () => {
  const { error } = await fixture.orgA.users.owner.client
    .from("projects")
    .insert({
      organization_id: fixture.orgB.id,
      created_by: fixture.orgA.users.owner.id,
      title: "Cross-org write attempt",
    })
    .select("id")
    .single();

  assert(error !== null, "wrote a project into another organization");
});

Deno.test("projects: a client cannot create one at all", async () => {
  // Section 7.2 gives clients read-only access to their own projects.
  const { error } = await fixture.orgA.users.client.client
    .from("projects")
    .insert({
      organization_id: fixture.orgA.id,
      created_by: fixture.orgA.users.client.id,
      title: "Client write attempt",
    })
    .select("id")
    .single();

  assert(error !== null, "client was able to create a project");
});

Deno.test("projects: fetching another org's project by id returns nothing", async () => {
  const { data: foreign } = await admin
    .from("projects")
    .insert({
      organization_id: fixture.orgB.id,
      created_by: fixture.orgB.users.owner.id,
      title: "Org B private",
    })
    .select("id")
    .single();

  // Null rather than an error: the app cannot distinguish "does not exist"
  // from "not yours", which is what stops it leaking that the row exists.
  const { data, error } = await fixture.orgA.users.owner.client
    .from("projects")
    .select("id")
    .eq("id", foreign!.id)
    .maybeSingle();

  assertEquals(error?.code ?? null, null);
  assertEquals(data, null, "read a project belonging to another organization");
});

/**
 * The client-write triggers from migrations 005/006. Written in Block A and
 * never exercised until now — they are the only thing stopping a client from
 * editing amounts on a document they are being asked to agree to.
 */
Deno.test("proposals: a client can approve a sent proposal", async () => {
  const { data: proposal } = await admin
    .from("proposals")
    .insert({
      organization_id: fixture.orgA.id,
      client_id: fixture.orgA.users.client.id,
      title: "Approvable",
      subtotal_cents: 10000,
      total_cents: 10000,
      status: "sent",
    })
    .select("id")
    .single();

  const { data, error } = await fixture.orgA.users.client.client
    .from("proposals")
    .update({ approved_at: new Date().toISOString() })
    .eq("id", proposal!.id)
    .select("id, status, approved_at")
    .single();

  assertEquals(error?.code ?? null, null, error?.message ?? "");
  // The trigger flips status itself, so the client app only ever writes
  // approved_at and never touches status directly.
  assertEquals(data?.status, "approved", "trigger did not auto-approve");
  assert(data?.approved_at !== null);
});

Deno.test("proposals: a client cannot approve a draft", async () => {
  const { data: proposal } = await admin
    .from("proposals")
    .insert({
      organization_id: fixture.orgA.id,
      client_id: fixture.orgA.users.client.id,
      title: "Still a draft",
      subtotal_cents: 5000,
      total_cents: 5000,
      status: "draft",
    })
    .select("id")
    .single();

  const { error } = await fixture.orgA.users.client.client
    .from("proposals")
    .update({ approved_at: new Date().toISOString() })
    .eq("id", proposal!.id)
    .select("id");

  assert(error !== null, "client approved a proposal that was never sent");
});

Deno.test("proposals: a client cannot alter the amount while approving", async () => {
  const { data: proposal } = await admin
    .from("proposals")
    .insert({
      organization_id: fixture.orgA.id,
      client_id: fixture.orgA.users.client.id,
      title: "Amount tamper attempt",
      subtotal_cents: 100000,
      total_cents: 100000,
      status: "sent",
    })
    .select("id")
    .single();

  const { error } = await fixture.orgA.users.client.client
    .from("proposals")
    .update({ approved_at: new Date().toISOString(), total_cents: 1 })
    .eq("id", proposal!.id)
    .select("id");

  assert(error !== null, "client changed the total while approving");

  const { data: after } = await admin
    .from("proposals")
    .select("total_cents, status")
    .eq("id", proposal!.id)
    .single();
  assertEquals(after?.total_cents, 100000, "amount was modified");
  assertEquals(after?.status, "sent", "status changed despite the rejection");
});

Deno.test("invoices: a client cannot mark an invoice paid", async () => {
  // `paid` is reachable only from the payment_intent.succeeded Edge Function
  // via the service role. A client marking their own invoice paid would be
  // straightforward theft.
  await admin.from("client_feature_toggles").upsert(
    {
      organization_id: fixture.orgA.id,
      feature_key: "client_payments",
      is_enabled: true,
    },
    { onConflict: "organization_id,feature_key" },
  );

  const { data: invoice } = await admin
    .from("invoices")
    .insert({
      organization_id: fixture.orgA.id,
      client_id: fixture.orgA.users.client.id,
      title: "Self-pay attempt",
      subtotal_cents: 25000,
      total_cents: 25000,
      status: "sent",
    })
    .select("id")
    .single();

  const { error } = await fixture.orgA.users.client.client
    .from("invoices")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("id", invoice!.id)
    .select("id");

  assert(error !== null, "client marked their own invoice paid");

  const { data: after } = await admin
    .from("invoices")
    .select("status, paid_at")
    .eq("id", invoice!.id)
    .single();
  assertEquals(after?.status, "sent");
  assertEquals(after?.paid_at, null);
});

Deno.test("line_items: a client cannot add items to their own proposal", async () => {
  const { data: proposal } = await admin
    .from("proposals")
    .insert({
      organization_id: fixture.orgA.id,
      client_id: fixture.orgA.users.client.id,
      title: "Line item tamper",
      subtotal_cents: 10000,
      total_cents: 10000,
      status: "sent",
    })
    .select("id")
    .single();

  const { error } = await fixture.orgA.users.client.client
    .from("line_items")
    .insert({
      organization_id: fixture.orgA.id,
      parent_type: "proposal",
      parent_id: proposal!.id,
      description: "Discount I added myself",
      quantity: 1,
      unit_price_cents: -9000,
      total_cents: -9000,
      sort_order: 99,
    })
    .select("id");

  assert(error !== null, "client wrote a line item");
});

Deno.test("line_items: the polymorphic parent must actually exist", async () => {
  // Migration 007 validates this with a trigger, since parent_id cannot have a
  // real foreign key across two possible tables.
  const { error } = await admin.from("line_items").insert({
    organization_id: fixture.orgA.id,
    parent_type: "proposal",
    parent_id: "00000000-0000-0000-0000-000000000000",
    description: "Orphan",
    quantity: 1,
    unit_price_cents: 100,
    total_cents: 100,
    sort_order: 0,
  });

  assert(error !== null, "wrote a line item pointing at a nonexistent parent");
});

Deno.test("teardown", async () => {
  await fixture.cleanup();
});
