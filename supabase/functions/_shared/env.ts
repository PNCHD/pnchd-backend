/**
 * Fail loudly at startup on a missing secret rather than at 3am on a live
 * webhook. A misconfigured function that boots and then silently 500s on every
 * delivery is much harder to diagnose than one that refuses to start.
 */
export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export function optionalEnv(name: string): string | undefined {
  return Deno.env.get(name) || undefined;
}
