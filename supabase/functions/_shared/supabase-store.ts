// EntitlementStore backed by Supabase with the service-role client (Edge Functions only).

import { DEFAULT_BUNDLE_ID, DEFAULT_PRODUCT_IDS, type EntitlementRow, type EntitlementStore } from "./entitlements.ts";

// deno-lint-ignore no-explicit-any
type AdminClient = any;

export function supabaseEntitlementStore(admin: AdminClient): EntitlementStore {
  return {
    async findByOriginalTransactionId(id) {
      const { data, error } = await admin.from("entitlements").select("*").eq("original_transaction_id", id).maybeSingle();
      if (error) throw error;
      return data as EntitlementRow | null;
    },
    async userExists(id) {
      const { data, error } = await admin.auth.admin.getUserById(id);
      if (error && error.status !== 404) throw error;
      return Boolean(data?.user);
    },
    async upsert(row) {
      const { id: _id, ...fields } = row;
      const { error } = await admin.from("entitlements").upsert(fields, { onConflict: "original_transaction_id" });
      if (error) throw error;
    },
    async notificationSeen(uuid) {
      const { data, error } = await admin.from("apple_notifications_seen").select("notification_uuid").eq("notification_uuid", uuid).maybeSingle();
      if (error) throw error;
      return data !== null;
    },
    async markNotificationSeen(uuid) {
      const { error } = await admin.from("apple_notifications_seen").upsert({ notification_uuid: uuid }, { ignoreDuplicates: true });
      if (error) throw error;
    },
  };
}

export function appleConfigFromEnv(env: { get(name: string): string | undefined }) {
  return {
    bundleId: env.get("APPLE_BUNDLE_ID") ?? DEFAULT_BUNDLE_ID,
    productIds: env.get("APPLE_PRODUCT_IDS")?.split(",").map((s) => s.trim()) ?? DEFAULT_PRODUCT_IDS,
  };
}

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
