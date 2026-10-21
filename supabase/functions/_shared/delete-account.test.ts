import { test } from "node:test";
import assert from "node:assert/strict";
import { deleteAccount, passwordAgeSeconds, USER_TABLES, type DeletionOps } from "./delete-account.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const NOW = 1_800_000_000;

function recorder(failAt?: string) {
  const calls: string[] = [];
  const step = (name: string) => async () => {
    calls.push(name);
    if (name === failAt) throw new Error(`failed at ${name}`);
  };
  const ops: DeletionOps = {
    revokeSessions: step("revoke"),
    deleteStorageFolder: step("storage"),
    deleteRows: async (table) => step(`rows:${table}`)(),
    deleteAuthUser: step("auth"),
  };
  return { calls, ops };
}

const fresh = { sub: USER, amr: [{ method: "password", timestamp: NOW - 60 }] };

test("deletion runs in the KTD14 order with the Auth user last", async () => {
  const { calls, ops } = recorder();
  const res = await deleteAccount(USER, fresh, ops, NOW);
  assert.equal(res.httpStatus, 200);
  assert.deepEqual(calls, ["revoke", "storage", ...USER_TABLES.map((t) => `rows:${t}`), "storage", "auth"]);
});

test("audit rows and closed months are deleted too", () => {
  assert.ok(USER_TABLES.includes("trip_audit_log"));
  assert.ok(USER_TABLES.includes("closed_months"));
});

test("a sign-in older than 10 minutes asks for the password again", async () => {
  const { calls, ops } = recorder();
  const res = await deleteAccount(USER, { sub: USER, amr: [{ method: "password", timestamp: NOW - 11 * 60 }] }, ops, NOW);
  assert.deepEqual([res.httpStatus, res.body.error], [401, "reauth_required"]);
  assert.deepEqual(calls, []);
});

test("a token refreshed without a password does not count as recent", async () => {
  const { ops } = recorder();
  const res = await deleteAccount(USER, { sub: USER, amr: [{ method: "token_refresh", timestamp: NOW }] }, ops, NOW);
  assert.equal(res.body.error, "reauth_required");
});

test("the newest password sign-in counts", () => {
  assert.equal(passwordAgeSeconds({ amr: [{ method: "password", timestamp: NOW - 900 }, { method: "password", timestamp: NOW - 30 }] }, NOW), 30);
});

test("a failure part-way leaves the Auth user (and its entitlements) in place for a retry", async () => {
  const first = recorder("rows:trips");
  await assert.rejects(deleteAccount(USER, fresh, first.ops, NOW));
  assert.ok(!first.calls.includes("auth"));
  const retry = recorder();
  const res = await deleteAccount(USER, fresh, retry.ops, NOW);
  assert.equal(res.httpStatus, 200);
  assert.equal(retry.calls.at(-1), "auth");
});

test("a token for another user is refused", async () => {
  const { calls, ops } = recorder();
  const res = await deleteAccount(USER, { ...fresh, sub: "someone-else" }, ops, NOW);
  assert.equal(res.httpStatus, 401);
  assert.deepEqual(calls, []);
});
