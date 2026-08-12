/**
 * HMAC-SHA256 verification for providers that sign with a plain digest rather
 * than a structured header (Docuseal). Stripe has its own scheme and uses the
 * SDK instead.
 */

const encoder = new TextEncoder();

export async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Constant-time string comparison.
 *
 * A plain `===` short-circuits on the first differing byte, so response time
 * leaks how much of a guessed signature was correct — enough to forge one byte
 * at a time. Always compare secrets and digests this way.
 */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

/** Tolerates an optional `sha256=` prefix and differing hex case. */
export async function verifyHmacSignature(
  secret: string,
  payload: string,
  providedSignature: string | null,
): Promise<boolean> {
  if (!providedSignature) return false;
  const normalized = providedSignature.replace(/^sha256=/i, "").trim().toLowerCase();
  const expected = await hmacSha256Hex(secret, payload);
  return timingSafeEqual(expected, normalized);
}
