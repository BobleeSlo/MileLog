// App Store Server API client: "Get All Subscription Statuses" with a JWT signed by
// the In-App Purchase key held in function secrets (never in the app or the repo).

import type { StatusLookup, SubscriptionStatus } from "./entitlements.ts";

export interface ApiKey {
  keyId: string;
  issuerId: string;
  /** PKCS#8 PEM of the .p8 key. */
  privateKeyPem: string;
  bundleId: string;
}

/** The endpoint follows the verified transaction's environment. */
export function apiBaseURL(environment: string): string {
  return environment === "Sandbox"
    ? "https://api.storekit-sandbox.itunes.apple.com"
    : "https://api.storekit.itunes.apple.com";
}

const b64url = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const json64 = (v: unknown) => b64url(new TextEncoder().encode(JSON.stringify(v)));

export async function apiToken(key: ApiKey, now = Date.now()): Promise<string> {
  const pem = key.privateKeyPem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const signingKey = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const iat = Math.floor(now / 1000);
  const unsigned = `${json64({ alg: "ES256", kid: key.keyId, typ: "JWT" })}.${json64({
    iss: key.issuerId, iat, exp: iat + 300, aud: "appstoreconnect-v1", bid: key.bundleId,
  })}`;
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signingKey, new TextEncoder().encode(unsigned)));
  return `${unsigned}.${b64url(sig)}`;
}

export function appStoreStatusLookup(key: ApiKey, fetchImpl: typeof fetch = fetch): StatusLookup {
  return async (originalTransactionId, environment) => {
    const url = `${apiBaseURL(environment)}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`;
    const res = await fetchImpl(url, { headers: { Authorization: `Bearer ${await apiToken(key)}` } });
    if (!res.ok) return null;
    const body = await res.json() as { data?: { lastTransactions?: (SubscriptionStatus & { originalTransactionId: string })[] }[] };
    for (const group of body.data ?? []) {
      const match = group.lastTransactions?.find((t) => t.originalTransactionId === originalTransactionId);
      if (match) return { status: match.status, signedTransactionInfo: match.signedTransactionInfo, signedRenewalInfo: match.signedRenewalInfo };
    }
    return null;
  };
}
