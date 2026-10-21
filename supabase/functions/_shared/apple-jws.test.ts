// Runs under `node --test` (Node 24 strips the types) and `deno test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { JwsError, verifyAppleJWS } from "./apple-jws.ts";
import { makeChain, signJWS } from "./test-signing.ts";

const rejects = (p: Promise<unknown>, code: string) =>
  assert.rejects(p, (e: unknown) => e instanceof JwsError && e.code === code);

test("a JWS signed by a trusted chain verifies and returns its payload", async () => {
  const chain = await makeChain();
  const jws = await signJWS(chain, { bundleId: "BT1.MileLog", signedDate: Date.parse("2026-10-21") });
  const payload = await verifyAppleJWS<{ bundleId: string }>(jws, { trustedRoots: [chain.rootSha256] });
  assert.equal(payload.bundleId, "BT1.MileLog");
});

test("a chain to any other root is rejected", async () => {
  const chain = await makeChain();
  const jws = await signJWS(chain, { signedDate: Date.now() });
  await rejects(verifyAppleJWS(jws), "untrusted_root"); // pinned Apple root
});

test("a tampered payload fails the signature check", async () => {
  const chain = await makeChain();
  const jws = await signJWS(chain, { productId: "monthly", signedDate: Date.now() });
  const [h, , s] = jws.split(".");
  const forged = btoa(JSON.stringify({ productId: "yearly", signedDate: Date.now() })).replace(/=+$/, "");
  await rejects(verifyAppleJWS(`${h}.${forged}.${s}`, { trustedRoots: [chain.rootSha256] }), "bad_signature");
});

test("a JWS signed by a key outside the chain is rejected", async () => {
  const chain = await makeChain();
  const other = await makeChain();
  const jws = await signJWS(chain, { signedDate: Date.now() }, other.leaf);
  await rejects(verifyAppleJWS(jws, { trustedRoots: [chain.rootSha256] }), "bad_signature");
});

test("a leaf without Apple's receipt-signing OID is rejected", async () => {
  const chain = await makeChain({ leafOid: "1.2.3.4" });
  const jws = await signJWS(chain, { signedDate: Date.now() });
  await rejects(verifyAppleJWS(jws, { trustedRoots: [chain.rootSha256] }), "bad_chain");
});

test("an intermediate swapped from another chain breaks the chain", async () => {
  const chain = await makeChain();
  const other = await makeChain();
  const mixed = { ...chain, intermediate: other.intermediate };
  const jws = await signJWS(mixed, { signedDate: Date.now() });
  await rejects(verifyAppleJWS(jws, { trustedRoots: [chain.rootSha256] }), "bad_chain");
});

test("a certificate expired at the payload's signedDate is rejected", async () => {
  const chain = await makeChain({ notAfter: new Date("2025-01-01T00:00:00Z") });
  const jws = await signJWS(chain, { signedDate: Date.parse("2026-10-21") });
  await rejects(verifyAppleJWS(jws, { trustedRoots: [chain.rootSha256] }), "expired_certificate");
});

test("garbage input is malformed", async () => {
  await rejects(verifyAppleJWS("not-a-jws"), "malformed");
});
