import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { requireEnv } from "./env.ts";

/**
 * Service-role client. Deliberately bypasses RLS — Edge Functions are trusted
 * server code writing tables that have no client write policies at all
 * (module_subscriptions, notifications, webhook_events).
 *
 * SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically into
 * deployed functions by the platform.
 *
 * persistSession/autoRefreshToken are off: there is no user session here and no
 * storage to persist into, and the refresh timer would keep the isolate alive.
 */
export function createAdminClient(): SupabaseClient {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
