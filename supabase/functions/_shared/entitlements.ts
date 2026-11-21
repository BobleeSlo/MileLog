// Entitlement rules shared by verify-purchase and apple-notifications. Pure apart
// from the injected store and status lookup, so it runs under `node --test`.

import { JwsError, verifyAppleJWS } from "./apple-jws.ts";

export type Status = "active" | "grace" | "billing_retry" | "expired" | "revoked";

export interface EntitlementRow {
  id?: string;
  user_id: string;
  source: "apple" | "complimentary";
  original_transaction_id: string | null;
  product_id: string | null;
  status: Status;
  expires_at: string | null;
  environment: string | null;
  last_signed_at: string | null;
}

export interface EntitlementStore {
  findByOriginalTransactionId(id: string): Promise<EntitlementRow | null>;
  userExists(id: string): Promise<boolean>;
  /** Insert or update, keyed by original_transaction_id. */
  upsert(row: EntitlementRow): Promise<void>;
  notificationSeen(uuid: string): Promise<boolean>;
  markNotificationSeen(uuid: string): Promise<void>;
}

export interface AppleConfig {
  bundleId: string;
  productIds: string[];
  /** Tests pass their own root; production uses the pinned Apple Root CA G3. */
  trustedRoots?: string[];
}

export interface TransactionPayload {
  bundleId: string;
  productId: string;
  originalTransactionId: string;
  transactionId?: string;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
  signedDate: number;
  environment: string;
}

export interface RenewalPayload {
  originalTransactionId: string;
  productId?: string;
  autoRenewProductId?: string;
  gracePeriodExpiresDate?: number;
  signedDate: number;
  environment: string;
}

/** Current status from the App Store Server API ("Get All Subscription Statuses"). */
export interface SubscriptionStatus {
  status: number;
  signedTransactionInfo: string;
  signedRenewalInfo?: string;
}

export type StatusLookup = (originalTransactionId: string, environment: string) => Promise<SubscriptionStatus | null>;

export interface Result {
  httpStatus: number;
  body: Record<string, unknown>;
}

export const DEFAULT_BUNDLE_ID = "BT1.MileLog";
export const DEFAULT_PRODUCT_IDS = ["BT1.MileLog.paid.monthly", "BT1.MileLog.paid.yearly"];
export const MAX_NOTIFICATION_BYTES = 64 * 1024;

/** KTD8: active and grace period are Paid; everything else is Free. */
export function isPaid(row: Pick<EntitlementRow, "status" | "expires_at">, now: Date): boolean {
  if (row.status !== "active" && row.status !== "grace") return false;
  return row.expires_at === null || new Date(row.expires_at) > now;
}

/** App Store Server API status codes. */
export function statusFromCode(code: number | undefined): Status | null {
  switch (code) {
    case 1: return "active";
    case 2: return "expired";
    case 3: return "billing_retry";
    case 4: return "grace";
    case 5: return "revoked";
    default: return null;
  }
}

/** Status for a notification; null means "no change of status, keep what is stored". */
export function statusFromNotification(type: string, subtype: string | undefined, code: number | undefined, tx: TransactionPayload): Status | null {
  if (tx.revocationDate) return "revoked";
  const fromCode = statusFromCode(code);
  if (fromCode) return fromCode;
  switch (type) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "REFUND_REVERSED":
      return "active";
    case "DID_FAIL_TO_RENEW":
      return subtype === "GRACE_PERIOD" ? "grace" : "billing_retry";
    case "GRACE_PERIOD_EXPIRED":
      return "billing_retry";
    case "EXPIRED":
      return "expired";
    case "REFUND":
    case "REVOKE":
      return "revoked";
    default:
      return null;
  }
}

/**
 * The row to write, or null to leave the stored row alone: a row never changes
 * user, and a payload signed before the last applied one is ignored.
 */
export function nextRow(existing: EntitlementRow | null, update: EntitlementRow): EntitlementRow | null {
  if (!existing) return update;
  if (existing.user_id !== update.user_id) return null;
  if (existing.last_signed_at && update.last_signed_at && new Date(update.last_signed_at) < new Date(existing.last_signed_at)) return null;
  return { ...update, id: existing.id };
}

function expiryFor(status: Status, tx: TransactionPayload, renewal: RenewalPayload | null): string | null {
  const ms = status === "grace" ? (renewal?.gracePeriodExpiresDate ?? tx.expiresDate) : tx.expiresDate;
  return ms ? new Date(ms).toISOString() : null;
}

function checkApp(config: AppleConfig, tx: TransactionPayload, renewal: RenewalPayload | null) {
  if (tx.bundleId !== config.bundleId) throw new JwsError("wrong_app");
  if (!config.productIds.includes(tx.productId)) throw new JwsError("unknown_product");
  if (renewal) {
    if (renewal.originalTransactionId !== tx.originalTransactionId) throw new JwsError("mismatched_renewal");
    for (const id of [renewal.productId, renewal.autoRenewProductId]) {
      if (id && !config.productIds.includes(id)) throw new JwsError("unknown_product");
    }
  }
}

const verify = <T>(jws: string, config: AppleConfig) => verifyAppleJWS<T>(jws, { trustedRoots: config.trustedRoots });
const lower = (s: string | undefined) => (s ? s.toLowerCase() : undefined);

export interface VerifyPurchaseDeps {
  store: EntitlementStore;
  lookupStatus: StatusLookup;
  config: AppleConfig;
  now?: () => Date;
}

/**
 * verify-purchase: the app sends a signed transaction right after a purchase,
 * restore or update. The transaction only identifies the subscription; the status
 * written comes from the App Store Server API (KTD5), so a replayed old
 * transaction can't re-activate a refunded one.
 */
export async function verifyPurchase(callerId: string, signedTransaction: unknown, deps: VerifyPurchaseDeps): Promise<Result> {
  const { store, config } = deps;
  const caller = callerId.toLowerCase();
  if (typeof signedTransaction !== "string") return { httpStatus: 400, body: { error: "missing_transaction" } };

  let tx: TransactionPayload;
  try {
    tx = await verify<TransactionPayload>(signedTransaction, config);
    checkApp(config, tx, null);
  } catch (e) {
    return { httpStatus: 400, body: { error: e instanceof JwsError ? e.code : "invalid_transaction" } };
  }

  // KTD6: an Apple subscription bound to another existing account is never re-bound.
  const existing = await store.findByOriginalTransactionId(tx.originalTransactionId);
  const token = lower(tx.appAccountToken);
  if (existing && existing.user_id !== caller) return { httpStatus: 409, body: { error: "other_account" } };
  if (token && token !== caller && await store.userExists(token)) return { httpStatus: 409, body: { error: "other_account" } };
  if (!token && !existing) return { httpStatus: 409, body: { error: "unbound_transaction" } };

  const current = await deps.lookupStatus(tx.originalTransactionId, tx.environment);
  if (!current) return { httpStatus: 502, body: { error: "status_unavailable" } };

  let latest: TransactionPayload;
  let renewal: RenewalPayload | null = null;
  try {
    latest = await verify<TransactionPayload>(current.signedTransactionInfo, config);
    if (current.signedRenewalInfo) renewal = await verify<RenewalPayload>(current.signedRenewalInfo, config);
    checkApp(config, latest, renewal);
    if (latest.originalTransactionId !== tx.originalTransactionId) throw new JwsError("mismatched_status");
  } catch (e) {
    return { httpStatus: 502, body: { error: e instanceof JwsError ? e.code : "invalid_status" } };
  }

  const status: Status = latest.revocationDate ? "revoked" : (statusFromCode(current.status) ?? "expired");
  const row = nextRow(existing, {
    user_id: caller,
    source: "apple",
    original_transaction_id: tx.originalTransactionId,
    product_id: latest.productId,
    status,
    expires_at: expiryFor(status, latest, renewal),
    environment: latest.environment,
    last_signed_at: new Date(Math.max(latest.signedDate, renewal?.signedDate ?? 0)).toISOString(),
  });
  if (row) await store.upsert(row);
  const written = row ?? existing!;
  const now = (deps.now ?? (() => new Date()))();
  return {
    httpStatus: 200,
    body: { plan: isPaid(written, now) ? "paid" : "free", status: written.status, expires_at: written.expires_at, environment: written.environment },
  };
}

export interface NotificationDeps {
  store: EntitlementStore;
  config: AppleConfig;
}

interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  signedDate: number;
  data?: {
    bundleId?: string;
    environment?: string;
    status?: number;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

/**
 * apple-notifications: App Store Server Notifications V2. Apple sends no Supabase
 * session, so the signature, bundle and product checks are the only gate (KTD7).
 * Unknown or deleted users get 200 without a write so Apple stops retrying.
 */
export async function handleNotification(rawBody: string, deps: NotificationDeps): Promise<Result> {
  const { store, config } = deps;
  if (new TextEncoder().encode(rawBody).length > MAX_NOTIFICATION_BYTES) return { httpStatus: 413, body: { error: "too_large" } };

  let n: NotificationPayload;
  let tx: TransactionPayload | null = null;
  let renewal: RenewalPayload | null = null;
  try {
    const { signedPayload } = JSON.parse(rawBody);
    n = await verify<NotificationPayload>(signedPayload, config);
    if (n.data?.bundleId !== config.bundleId) throw new JwsError("wrong_app");
    if (n.data.signedTransactionInfo) tx = await verify<TransactionPayload>(n.data.signedTransactionInfo, config);
    if (n.data.signedRenewalInfo) renewal = await verify<RenewalPayload>(n.data.signedRenewalInfo, config);
    if (tx) checkApp(config, tx, renewal);
  } catch (e) {
    return { httpStatus: 400, body: { error: e instanceof JwsError ? e.code : "invalid_payload" } };
  }

  if (!tx) return { httpStatus: 200, body: { result: "ignored" } }; // TEST and summary notifications
  if (await store.notificationSeen(n.notificationUUID)) return { httpStatus: 200, body: { result: "duplicate" } };

  // The stored row decides the user first; the token only for a first sighting.
  const existing = await store.findByOriginalTransactionId(tx.originalTransactionId);
  const token = lower(tx.appAccountToken);
  const userId = existing?.user_id ?? (token && await store.userExists(token) ? token : null);
  if (!userId) {
    await store.markNotificationSeen(n.notificationUUID);
    return { httpStatus: 200, body: { result: "unknown_user" } };
  }

  const status = statusFromNotification(n.notificationType, n.subtype, n.data?.status, tx)
    ?? existing?.status
    ?? (tx.expiresDate && tx.expiresDate > n.signedDate ? "active" : "expired");
  const row = nextRow(existing, {
    user_id: userId,
    source: "apple",
    original_transaction_id: tx.originalTransactionId,
    product_id: tx.productId,
    status,
    expires_at: expiryFor(status, tx, renewal),
    environment: tx.environment,
    last_signed_at: new Date(n.signedDate).toISOString(),
  });
  if (row) await store.upsert(row);
  await store.markNotificationSeen(n.notificationUUID);
  return { httpStatus: 200, body: { result: row ? "updated" : "stale" } };
}
