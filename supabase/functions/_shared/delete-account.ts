// Account deletion (KTD14). Pure apart from the injected operations, so the
// order and the checks are tested under `node --test`.
//
// Order: revoke sessions → delete receipt photos → delete rows → delete photos
// again (in case an upload landed in between) → delete the Auth user, whose
// entitlement rows go with it by cascade, last, so a failed run never leaves a
// paying user Free. Every step is idempotent, so a retry finishes the job.
//
// The lock trigger (trip_lock_guard) is BEFORE UPDATE only, so deleting locked
// trips needs no bypass.

import { base64UrlDecode } from "./apple-jws.ts";
import type { Result } from "./entitlements.ts";

export const REAUTH_WINDOW_SECONDS = 10 * 60;

/** Tables holding the user's rows, children before parents. */
export const USER_TABLES = [
  "trip_audit_log",
  "receipts",
  "closed_months",
  "trips", // trip_points go with their trips
  "vehicles",
  "customers",
  "user_settings",
] as const;

export interface DeletionOps {
  revokeSessions(): Promise<void>;
  deleteStorageFolder(userId: string): Promise<void>;
  deleteRows(table: string, userId: string): Promise<void>;
  deleteAuthUser(userId: string): Promise<void>;
}

interface Claims {
  sub?: string;
  amr?: { method: string; timestamp: number }[];
}

/** Seconds since the session's last password sign-in, from the access token's amr claim. */
export function passwordAgeSeconds(claims: Claims, nowSeconds: number): number | null {
  const password = (claims.amr ?? []).filter((a) => a.method === "password").map((a) => a.timestamp);
  if (password.length === 0) return null;
  return nowSeconds - Math.max(...password);
}

export function decodeClaims(jwt: string): Claims {
  return JSON.parse(new TextDecoder().decode(base64UrlDecode(jwt.split(".")[1] ?? "")));
}

/**
 * @param userId the user the server resolved from the token (never taken from the body)
 */
export async function deleteAccount(userId: string, claims: Claims, ops: DeletionOps, nowSeconds = Date.now() / 1000): Promise<Result> {
  if (claims.sub && claims.sub !== userId) return { httpStatus: 401, body: { error: "not_signed_in" } };
  const age = passwordAgeSeconds(claims, nowSeconds);
  if (age === null || age > REAUTH_WINDOW_SECONDS) return { httpStatus: 401, body: { error: "reauth_required" } };

  await ops.revokeSessions();
  await ops.deleteStorageFolder(userId);
  for (const table of USER_TABLES) await ops.deleteRows(table, userId);
  await ops.deleteStorageFolder(userId);
  await ops.deleteAuthUser(userId);
  return { httpStatus: 200, body: { deleted: true } };
}
