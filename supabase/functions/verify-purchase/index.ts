// POST { signedTransaction } with the user's session. Verifies the transaction,
// confirms its status with the App Store Server API and records the entitlement.
// Secrets: APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID, APPLE_IAP_PRIVATE_KEY.

import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyPurchase } from "../_shared/entitlements.ts";
import { appStoreStatusLookup } from "../_shared/app-store-api.ts";
import { appleConfigFromEnv, json, supabaseEntitlementStore } from "../_shared/supabase-store.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const config = appleConfigFromEnv(Deno.env);
const lookupStatus = appStoreStatusLookup({
  keyId: Deno.env.get("APPLE_IAP_KEY_ID")!,
  issuerId: Deno.env.get("APPLE_IAP_ISSUER_ID")!,
  privateKeyPem: Deno.env.get("APPLE_IAP_PRIVATE_KEY")!,
  bundleId: config.bundleId,
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth } = jwt ? await admin.auth.getUser(jwt) : { data: { user: null } };
  if (!auth.user) return json(401, { error: "not_signed_in" });

  let body: { signedTransaction?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_body" });
  }
  try {
    const result = await verifyPurchase(auth.user.id, body.signedTransaction, {
      store: supabaseEntitlementStore(admin),
      lookupStatus,
      config,
    });
    return json(result.httpStatus, result.body);
  } catch (e) {
    console.error("verify-purchase failed", e);
    return json(500, { error: "server_error" });
  }
});
