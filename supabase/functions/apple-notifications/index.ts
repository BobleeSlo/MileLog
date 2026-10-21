// App Store Server Notifications V2 webhook. Deployed with verify_jwt = false
// (supabase/config.toml): Apple's signed payload is the only credential.

import { createClient } from "npm:@supabase/supabase-js@2";
import { handleNotification, MAX_NOTIFICATION_BYTES } from "../_shared/entitlements.ts";
import { appleConfigFromEnv, json, supabaseEntitlementStore } from "../_shared/supabase-store.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const config = appleConfigFromEnv(Deno.env);

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const declared = Number(req.headers.get("Content-Length") ?? 0);
  if (declared > MAX_NOTIFICATION_BYTES) return json(413, { error: "too_large" });
  try {
    const result = await handleNotification(await req.text(), { store: supabaseEntitlementStore(admin), config });
    return json(result.httpStatus, result.body);
  } catch (e) {
    console.error("apple-notifications failed", e);
    return json(500, { error: "server_error" }); // Apple retries
  }
});
