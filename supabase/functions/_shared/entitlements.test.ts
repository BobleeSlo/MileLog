// U3 scenarios for verify-purchase and apple-notifications, with an in-memory store.
import { test } from "node:test";
import assert from "node:assert/strict";
import { handleNotification, isPaid, verifyPurchase, type EntitlementRow, type EntitlementStore, type SubscriptionStatus } from "./entitlements.ts";
import { apiBaseURL } from "./app-store-api.ts";
import { makeChain, signJWS, type TestChain } from "./test-signing.ts";

const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";
const GONE = "33333333-3333-4333-8333-333333333333";
const MONTHLY = "BT1.MileLog.paid.monthly";
const DAY = 86_400_000;
const NOW = Date.parse("2026-10-21T12:00:00Z");

function memoryStore(users = [ALICE, BOB]) {
  const rows = new Map<string, EntitlementRow>();
  const seen = new Set<string>();
  const store: EntitlementStore & { rows: Map<string, EntitlementRow>; writes: number } = {
    rows,
    writes: 0,
    async findByOriginalTransactionId(id) { return rows.get(id) ?? null; },
    async userExists(id) { return users.includes(id); },
    async upsert(row) { store.writes++; rows.set(row.original_transaction_id!, { ...row }); },
    async notificationSeen(uuid) { return seen.has(uuid); },
    async markNotificationSeen(uuid) { seen.add(uuid); },
  };
  return store;
}

let chain: TestChain;
const config = () => ({ bundleId: "BT1.MileLog", productIds: [MONTHLY, "BT1.MileLog.paid.yearly"], trustedRoots: [chain.rootSha256] });

function tx(over: Record<string, unknown> = {}) {
  return {
    bundleId: "BT1.MileLog", productId: MONTHLY, originalTransactionId: "1000", transactionId: "1000",
    appAccountToken: ALICE, expiresDate: NOW + 30 * DAY, signedDate: NOW, environment: "Production", ...over,
  };
}

/** Status lookup returning what the App Store Server API would say now. */
function lookup(status: number, over: Record<string, unknown> = {}, calls: string[] = []) {
  return async (orig: string, env: string): Promise<SubscriptionStatus | null> => {
    calls.push(`${apiBaseURL(env)}|${orig}`);
    return { status, signedTransactionInfo: await signJWS(chain, tx({ originalTransactionId: orig, environment: env, ...over })) };
  };
}

async function notification(type: string, txOver: Record<string, unknown> = {}, extra: Record<string, unknown> = {}) {
  const payload = {
    notificationType: type, notificationUUID: crypto.randomUUID(), signedDate: NOW,
    data: { bundleId: "BT1.MileLog", environment: "Production", signedTransactionInfo: await signJWS(chain, tx(txOver)) },
    ...extra,
  };
  return JSON.stringify({ signedPayload: await signJWS(chain, payload) });
}

test.before(async () => { chain = await makeChain(); });

test("a valid transaction for the caller creates an active entitlement with its expiry", async () => {
  const store = memoryStore();
  const res = await verifyPurchase(ALICE, await signJWS(chain, tx()), { store, lookupStatus: lookup(1), config: config(), now: () => new Date(NOW) });
  assert.equal(res.httpStatus, 200);
  assert.equal(res.body.plan, "paid");
  const row = store.rows.get("1000")!;
  assert.equal(row.user_id, ALICE);
  assert.equal(row.status, "active");
  assert.equal(row.expires_at, new Date(NOW + 30 * DAY).toISOString());
});

test("the same transaction sent twice leaves one row", async () => {
  const store = memoryStore();
  const jws = await signJWS(chain, tx());
  const deps = { store, lookupStatus: lookup(1), config: config() };
  await verifyPurchase(ALICE, jws, deps);
  await verifyPurchase(ALICE, jws, deps);
  assert.equal(store.rows.size, 1);
});

test("a transaction whose token is another user's is rejected and nothing changes", async () => {
  const store = memoryStore();
  const res = await verifyPurchase(BOB, await signJWS(chain, tx()), { store, lookupStatus: lookup(1), config: config() });
  assert.equal(res.httpStatus, 409);
  assert.equal(res.body.error, "other_account");
  assert.equal(store.writes, 0);
});

test("a subscription already bound to another account is never re-bound", async () => {
  const store = memoryStore();
  await verifyPurchase(ALICE, await signJWS(chain, tx()), { store, lookupStatus: lookup(1), config: config() });
  const res = await verifyPurchase(BOB, await signJWS(chain, tx({ appAccountToken: BOB })), { store, lookupStatus: lookup(1), config: config() });
  assert.equal(res.httpStatus, 409);
  assert.equal(store.rows.get("1000")!.user_id, ALICE);
});

test("a broken signature is rejected", async () => {
  const store = memoryStore();
  const other = await makeChain();
  const res = await verifyPurchase(ALICE, await signJWS(other, tx()), { store, lookupStatus: lookup(1), config: config() });
  assert.equal(res.httpStatus, 400);
  assert.equal(store.writes, 0);
});

test("another app's bundle ID is rejected", async () => {
  const res = await verifyPurchase(ALICE, await signJWS(chain, tx({ bundleId: "com.other.app" })), { store: memoryStore(), lookupStatus: lookup(1), config: config() });
  assert.deepEqual([res.httpStatus, res.body.error], [400, "wrong_app"]);
});

test("an unknown product ID is rejected", async () => {
  const res = await verifyPurchase(ALICE, await signJWS(chain, tx({ productId: "BT1.MileLog.lifetime" })), { store: memoryStore(), lookupStatus: lookup(1), config: config() });
  assert.deepEqual([res.httpStatus, res.body.error], [400, "unknown_product"]);
});

test("a sandbox purchase is stored as sandbox, looked up in sandbox, and lapses at its expiry", async () => {
  const store = memoryStore();
  const calls: string[] = [];
  const short = { environment: "Sandbox", expiresDate: NOW + 5 * 60_000 };
  const res = await verifyPurchase(ALICE, await signJWS(chain, tx(short)), { store, lookupStatus: lookup(1, short, calls), config: config(), now: () => new Date(NOW + 10 * 60_000) });
  assert.equal(calls[0], "https://api.storekit-sandbox.itunes.apple.com|1000");
  assert.equal(store.rows.get("1000")!.environment, "Sandbox");
  assert.equal(res.body.plan, "free");
});

test("a replayed transaction signed before a refund does not re-activate the row", async () => {
  const store = memoryStore();
  const old = await signJWS(chain, tx({ signedDate: NOW - 10 * DAY }));
  await verifyPurchase(ALICE, old, { store, lookupStatus: lookup(1), config: config() });
  const res = await verifyPurchase(ALICE, old, { store, lookupStatus: lookup(5, { revocationDate: NOW - DAY }), config: config() });
  assert.equal(res.body.plan, "free");
  assert.equal(store.rows.get("1000")!.status, "revoked");
});

test("a transaction without a token is accepted when its subscription already belongs to the caller", async () => {
  const store = memoryStore();
  await verifyPurchase(ALICE, await signJWS(chain, tx()), { store, lookupStatus: lookup(1), config: config() });
  const res = await verifyPurchase(ALICE, await signJWS(chain, tx({ appAccountToken: undefined })), { store, lookupStatus: lookup(1), config: config() });
  assert.equal(res.httpStatus, 200);
});

test("a transaction without a token for an unknown subscription is refused", async () => {
  const res = await verifyPurchase(ALICE, await signJWS(chain, tx({ appAccountToken: undefined })), { store: memoryStore(), lookupStatus: lookup(1), config: config() });
  assert.deepEqual([res.httpStatus, res.body.error], [409, "unbound_transaction"]);
});

test("a token whose user was deleted binds to the caller", async () => {
  const store = memoryStore();
  const res = await verifyPurchase(BOB, await signJWS(chain, tx({ appAccountToken: GONE })), { store, lookupStatus: lookup(1), config: config() });
  assert.equal(res.httpStatus, 200);
  assert.equal(store.rows.get("1000")!.user_id, BOB);
});

test("DID_RENEW extends the expiry", async () => {
  const store = memoryStore();
  await verifyPurchase(ALICE, await signJWS(chain, tx()), { store, lookupStatus: lookup(1, { signedDate: NOW - DAY }), config: config() });
  const res = await handleNotification(await notification("DID_RENEW", { expiresDate: NOW + 60 * DAY }), { store, config: config() });
  assert.equal(res.httpStatus, 200);
  assert.equal(store.rows.get("1000")!.expires_at, new Date(NOW + 60 * DAY).toISOString());
});

test("REFUND revokes the entitlement", async () => {
  const store = memoryStore();
  await verifyPurchase(ALICE, await signJWS(chain, tx()), { store, lookupStatus: lookup(1, { signedDate: NOW - DAY }), config: config() });
  await handleNotification(await notification("REFUND", { revocationDate: NOW }), { store, config: config() });
  assert.equal(store.rows.get("1000")!.status, "revoked");
});

test("EXPIRED after billing retry sets the status to expired", async () => {
  const store = memoryStore();
  await handleNotification(await notification("DID_FAIL_TO_RENEW"), { store, config: config() });
  assert.equal(store.rows.get("1000")!.status, "billing_retry");
  await handleNotification(await notification("EXPIRED", {}, { signedDate: NOW + DAY }), { store, config: config() });
  assert.equal(store.rows.get("1000")!.status, "expired");
});

test("a repeated notificationUUID is ignored", async () => {
  const store = memoryStore();
  const body = await notification("SUBSCRIBED");
  await handleNotification(body, { store, config: config() });
  const res = await handleNotification(body, { store, config: config() });
  assert.equal(res.body.result, "duplicate");
  assert.equal(store.writes, 1);
});

test("a notification older than the row's last applied signed date is ignored", async () => {
  const store = memoryStore();
  await handleNotification(await notification("DID_RENEW", { expiresDate: NOW + 60 * DAY }, { signedDate: NOW }), { store, config: config() });
  const res = await handleNotification(await notification("EXPIRED", {}, { signedDate: NOW - DAY }), { store, config: config() });
  assert.equal(res.body.result, "stale");
  assert.equal(store.rows.get("1000")!.status, "active");
});

test("a renewal for a deleted user answers 200 and writes nothing", async () => {
  const store = memoryStore();
  const res = await handleNotification(await notification("DID_RENEW", { appAccountToken: GONE }), { store, config: config() });
  assert.deepEqual([res.httpStatus, res.body.result, store.writes], [200, "unknown_user", 0]);
});

test("the stored row decides the user before the token", async () => {
  const store = memoryStore();
  await handleNotification(await notification("SUBSCRIBED"), { store, config: config() });
  await handleNotification(await notification("DID_RENEW", { appAccountToken: BOB }, { signedDate: NOW + DAY }), { store, config: config() });
  assert.equal(store.rows.get("1000")!.user_id, ALICE);
});

test("a notification for another app is rejected", async () => {
  const body = await notification("SUBSCRIBED", {}, { data: { bundleId: "com.other.app" } });
  const res = await handleNotification(body, { store: memoryStore(), config: config() });
  assert.equal(res.httpStatus, 400);
});

test("an oversized body is refused before parsing", async () => {
  const res = await handleNotification("x".repeat(70_000), { store: memoryStore(), config: config() });
  assert.equal(res.httpStatus, 413);
});

test("a grace period counts as Paid until the grace expiry", async () => {
  const store = memoryStore();
  const renewal = await signJWS(chain, { originalTransactionId: "1000", productId: MONTHLY, gracePeriodExpiresDate: NOW + 6 * DAY, signedDate: NOW, environment: "Production" });
  const payload = {
    notificationType: "DID_FAIL_TO_RENEW", subtype: "GRACE_PERIOD", notificationUUID: crypto.randomUUID(), signedDate: NOW,
    data: { bundleId: "BT1.MileLog", environment: "Production", signedTransactionInfo: await signJWS(chain, tx({ expiresDate: NOW - DAY })), signedRenewalInfo: renewal },
  };
  await handleNotification(JSON.stringify({ signedPayload: await signJWS(chain, payload) }), { store, config: config() });
  const row = store.rows.get("1000")!;
  assert.equal(row.status, "grace");
  assert.equal(row.expires_at, new Date(NOW + 6 * DAY).toISOString());
  assert.ok(isPaid(row, new Date(NOW)));
  assert.ok(!isPaid(row, new Date(NOW + 6 * DAY)));
  await handleNotification(await notification("GRACE_PERIOD_EXPIRED", {}, { signedDate: NOW + 7 * DAY }), { store, config: config() });
  assert.equal(store.rows.get("1000")!.status, "billing_retry");
});

test("an unavailable status lookup writes nothing and leaves a Paid row intact", async () => {
  const store = memoryStore();
  await verifyPurchase(ALICE, await signJWS(chain, tx()), { store, lookupStatus: lookup(1), config: config() });
  const before = { ...store.rows.get("1000")! };
  const res = await verifyPurchase(ALICE, await signJWS(chain, tx()), { store, lookupStatus: async () => null, config: config() });
  assert.deepEqual([res.httpStatus, res.body.error], [502, "status_unavailable"]);
  assert.deepEqual(store.rows.get("1000"), before);
});

test("a status for a different subscription is refused", async () => {
  const store = memoryStore();
  const wrong = async (): Promise<SubscriptionStatus> => ({ status: 1, signedTransactionInfo: await signJWS(chain, tx({ originalTransactionId: "2000" })) });
  const res = await verifyPurchase(ALICE, await signJWS(chain, tx()), { store, lookupStatus: wrong, config: config() });
  assert.deepEqual([res.httpStatus, res.body.error, store.writes], [502, "mismatched_status", 0]);
});

test("a missing transaction is a bad request", async () => {
  const res = await verifyPurchase(ALICE, undefined, { store: memoryStore(), lookupStatus: lookup(1), config: config() });
  assert.deepEqual([res.httpStatus, res.body.error], [400, "missing_transaction"]);
});

test("a notification without a transaction (e.g. TEST) is acknowledged without a write", async () => {
  const store = memoryStore();
  const payload = { notificationType: "TEST", notificationUUID: crypto.randomUUID(), signedDate: NOW, data: { bundleId: "BT1.MileLog", environment: "Production" } };
  const res = await handleNotification(JSON.stringify({ signedPayload: await signJWS(chain, payload) }), { store, config: config() });
  assert.deepEqual([res.httpStatus, res.body.result, store.writes], [200, "ignored", 0]);
});
