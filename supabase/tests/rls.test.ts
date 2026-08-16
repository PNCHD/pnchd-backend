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

Deno.test("teardown", async () => {
  await fixture.cleanup();
});
