// POST with the user's session. Deletes the account and all its cloud data
// (KTD14). Requires a password sign-in within the last 10 minutes.

import { createClient } from "npm:@supabase/supabase-js@2";
import { decodeClaims, deleteAccount } from "../_shared/delete-account.ts";
import { json } from "../_shared/supabase-store.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const BUCKET = "receipts";

async function deleteStorageFolder(userId: string) {
  const folder = userId.toLowerCase();
  for (;;) {
    const { data, error } = await admin.storage.from(BUCKET).list(folder, { limit: 100 });
    if (error) throw error;
    if (!data || data.length === 0) return;
    const { error: removeError } = await admin.storage.from(BUCKET).remove(data.map((f) => `${folder}/${f.name}`));
    if (removeError) throw removeError;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { error: "not_signed_in" });

  const { data, error } = await admin.auth.getUser(jwt);
  if (!data?.user) {
    // A retry after a deletion whose response was lost: the user is gone.
    const gone = error && /not exist|not found/i.test(error.message);
    return gone ? json(404, { error: "user_not_found" }) : json(401, { error: "not_signed_in" });
  }

  try {
    const result = await deleteAccount(data.user.id, decodeClaims(jwt), {
      revokeSessions: async () => {
        const { error } = await admin.auth.admin.signOut(jwt, "global");
        if (error) throw error;
      },
      deleteStorageFolder,
      deleteRows: async (table, userId) => {
        const { error } = await admin.from(table).delete().eq("user_id", userId);
        if (error) throw error;
      },
      deleteAuthUser: async (userId) => {
        const { error } = await admin.auth.admin.deleteUser(userId);
        if (error && error.status !== 404) throw error;
      },
    });
    return json(result.httpStatus, result.body);
  } catch (e) {
    console.error("delete-account failed", e);
    return json(500, { error: "server_error" }); // safe to retry
  }
});
