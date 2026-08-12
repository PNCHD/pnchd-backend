import { assertEquals } from "@std/assert";

import { hmacSha256Hex, timingSafeEqual, verifyHmacSignature } from "./hmac.ts";

const SECRET = "whsec_test_secret";
const BODY = '{"event_type":"form.completed","data":{"id":42}}';

Deno.test("hmacSha256Hex matches a known RFC 4231 vector", async () => {
  // Test case 1 from RFC 4231: key = 20 bytes of 0x0b, data = "Hi There".
  const key = "\x0b".repeat(20);
  assertEquals(
    await hmacSha256Hex(key, "Hi There"),
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
  );
});

Deno.test("hmacSha256Hex is deterministic", async () => {
  assertEquals(await hmacSha256Hex(SECRET, BODY), await hmacSha256Hex(SECRET, BODY));
});

Deno.test("hmacSha256Hex changes with the secret", async () => {
  const a = await hmacSha256Hex(SECRET, BODY);
  const b = await hmacSha256Hex("different_secret", BODY);
  assertEquals(a === b, false);
});

Deno.test("timingSafeEqual matches identical strings", () => {
  assertEquals(timingSafeEqual("abc123", "abc123"), true);
});

Deno.test("timingSafeEqual rejects differing strings and lengths", () => {
  assertEquals(timingSafeEqual("abc123", "abc124"), false);
  assertEquals(timingSafeEqual("abc", "abcd"), false);
  assertEquals(timingSafeEqual("", "a"), false);
});

Deno.test("verifyHmacSignature accepts a correct signature", async () => {
  const signature = await hmacSha256Hex(SECRET, BODY);
  assertEquals(await verifyHmacSignature(SECRET, BODY, signature), true);
});

Deno.test("verifyHmacSignature tolerates a sha256= prefix and mixed case", async () => {
  const signature = await hmacSha256Hex(SECRET, BODY);
  assertEquals(
    await verifyHmacSignature(SECRET, BODY, `sha256=${signature.toUpperCase()}`),
    true,
  );
});

Deno.test("verifyHmacSignature rejects a tampered body", async () => {
  const signature = await hmacSha256Hex(SECRET, BODY);
  const tampered = BODY.replace('"id":42', '"id":43');
  assertEquals(await verifyHmacSignature(SECRET, tampered, signature), false);
});

Deno.test("verifyHmacSignature rejects a signature from the wrong secret", async () => {
  const forged = await hmacSha256Hex("attacker_secret", BODY);
  assertEquals(await verifyHmacSignature(SECRET, BODY, forged), false);
});

Deno.test("verifyHmacSignature rejects a missing signature", async () => {
  assertEquals(await verifyHmacSignature(SECRET, BODY, null), false);
  assertEquals(await verifyHmacSignature(SECRET, BODY, ""), false);
});
