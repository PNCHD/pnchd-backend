import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Seeds real auth users and org data, then hands back a Supabase client
 * authenticated *as each user* — the whole point of this harness.
 *
 * Every check before this existed ran as service_role, which bypasses both RLS
 * and table grants. That blind spot hid two total-outage bugs (missing GRANTs,
 * and RLS recursion) behind a fully green test suite. Anything asserting access
 * control has to run as a real signed-in user or it proves nothing.
 */

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(
      `Missing ${name}. Run with:\n` +
        `  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... SUPABASE_ANON_KEY=... deno task rls`,
    );
  }
  return value;
}

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SERVICE_ROLE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const ANON_KEY = requireEnv("SUPABASE_ANON_KEY");

export const admin: SupabaseClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

export type Role = "owner" | "pro" | "client" | "driver" | "platform_admin";

export interface SeededUser {
  id: string;
  email: string;
  role: Role;
  /** Client scoped to this user's session — subject to RLS, like the real apps. */
  client: SupabaseClient;
}

export interface Org {
  id: string;
  users: Record<string, SeededUser>;
}

export interface Fixture {
  runId: string;
  orgA: Org;
  orgB: Org;
  cleanup: () => Promise<void>;
}

const PASSWORD = "test-password-not-a-secret";

async function createUser(
  runId: string,
  label: string,
  role: Role,
  organizationId: string,
): Promise<SeededUser> {
  const email = `rls-${runId}-${label}@example.test`;

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: PASSWORD,
    email_confirm: true,
    user_metadata: { role, full_name: `${label} ${runId}` },
  });
  if (error || !data.user) throw new Error(`createUser(${label}) failed: ${error?.message}`);

  // The handle_new_user trigger creates the profile with organization_id NULL;
  // the real signup flow fills it in, so we do the same here.
  const { error: profileError } = await admin
    .from("profiles")
    .update({ organization_id: organizationId, role })
    .eq("id", data.user.id);
  if (profileError) throw new Error(`profile update(${label}) failed: ${profileError.message}`);

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: signInError } = await client.auth.signInWithPassword({
    email,
    password: PASSWORD,
  });
  if (signInError) throw new Error(`signIn(${label}) failed: ${signInError.message}`);

  return { id: data.user.id, email, role, client };
}

async function createOrg(runId: string, label: string): Promise<string> {
  const { data, error } = await admin
    .from("organizations")
    .insert({ name: `RLS ${label} ${runId}` })
    .select("id")
    .single();
  if (error) throw new Error(`createOrg(${label}) failed: ${error.message}`);
  return data.id;
}

/**
 * Two organizations, so cross-org isolation is actually exercised. A
 * single-org fixture cannot tell "isolation works" apart from "there is no
 * other data to leak."
 */
export async function seed(): Promise<Fixture> {
  const runId = crypto.randomUUID().slice(0, 8);

  const orgAId = await createOrg(runId, "A");
  const orgBId = await createOrg(runId, "B");

  const orgA: Org = {
    id: orgAId,
    users: {
      owner: await createUser(runId, "a-owner", "owner", orgAId),
      pro: await createUser(runId, "a-pro", "pro", orgAId),
      client: await createUser(runId, "a-client", "client", orgAId),
      driver: await createUser(runId, "a-driver", "driver", orgAId),
      admin: await createUser(runId, "a-admin", "platform_admin", orgAId),
    },
  };

  const orgB: Org = {
    id: orgBId,
    users: {
      owner: await createUser(runId, "b-owner", "owner", orgBId),
      client: await createUser(runId, "b-client", "client", orgBId),
    },
  };

  const cleanup = async () => {
    const orgIds = [orgAId, orgBId];
    const userIds = [
      ...Object.values(orgA.users).map((u) => u.id),
      ...Object.values(orgB.users).map((u) => u.id),
    ];

    // Children before parents; FKs have no cascade.
    for (const table of [
      "notifications",
      "vehicle_locations",
      "vehicles",
      "line_items",
      "document_signers",
      "documents",
      "invoices",
      "proposals",
      "project_assignments",
      "projects",
      "client_feature_toggles",
      "module_subscriptions",
    ]) {
      await admin.from(table).delete().in("organization_id", orgIds);
    }
    await admin.from("profiles").delete().in("id", userIds);
    await admin.from("organizations").delete().in("id", orgIds);
    for (const id of userIds) await admin.auth.admin.deleteUser(id);
  };

  return { runId, orgA, orgB, cleanup };
}

/**
 * A signed-in user with NO organization — the state handle_new_user leaves a
 * profile in between clicking the magic link and finishing setup. Used to
 * exercise the real signup path under RLS.
 */
export async function seedUnattachedUser(
  runId: string,
): Promise<{ user: SeededUser; cleanup: () => Promise<void> }> {
  const email = `rls-${runId}-unattached@example.test`;

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: PASSWORD,
    email_confirm: true,
    user_metadata: { role: "owner", full_name: "Unattached Owner" },
  });
  if (error || !data.user) throw new Error(`createUser failed: ${error?.message}`);

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: signInError } = await client.auth.signInWithPassword({
    email,
    password: PASSWORD,
  });
  if (signInError) throw new Error(`signIn failed: ${signInError.message}`);

  const user: SeededUser = { id: data.user.id, email, role: "owner", client };

  const cleanup = async () => {
    const { data: profile } = await admin
      .from("profiles")
      .select("organization_id")
      .eq("id", user.id)
      .maybeSingle();
    await admin.from("profiles").delete().eq("id", user.id);
    if (profile?.organization_id) {
      await admin.from("organizations").delete().eq("id", profile.organization_id);
    }
    await admin.auth.admin.deleteUser(user.id);
  };

  return { user, cleanup };
}

/** Rows visible to this client, or the PostgREST error code if denied. */
export async function readable(
  client: SupabaseClient,
  table: string,
  columns = "id",
): Promise<{ count: number; errorCode: string | null }> {
  const { data, error } = await client.from(table).select(columns);
  return { count: data?.length ?? 0, errorCode: error?.code ?? null };
}
