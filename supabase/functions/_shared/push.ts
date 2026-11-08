// Shared FCM (HTTP v1) push delivery for every inbox notification writer.
//
// Callers write their public.notifications rows first, then pass exactly
// the recipients that got a genuinely new row here, so a retried webhook
// never pushes twice. Delivery is best effort: an FCM problem is logged and
// reported, never thrown at the caller's order/cancellation flow.
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleAuth } from "https://esm.sh/google-auth-library@9?target=deno";

/// Must match the channel created in android/.../MainActivity.kt. A
/// high-importance channel is what makes Android ring and show a banner
/// while the app is closed, instead of a silent status-bar icon.
export const ANDROID_CHANNEL_ID = "order_updates";

export type PushRecipient = { userId: string; title: string; body: string };
type PushTarget = { userId: string; token: string; copy: PushRecipient };

/// Every device of the recipients who allow push: device_tokens rows (0073)
/// plus the legacy profiles.fcm_token older app builds still write. A token
/// reaches one account only, and a device_tokens owner beats a stale legacy
/// copy, so a phone that changed hands stops getting the old account's
/// order updates.
export function pushTargets(
  copyByUserId: Map<string, PushRecipient>,
  enabledUserIds: Set<string>,
  deviceRows: { user_id: string; token: string }[],
  legacyRows: { id: string; fcm_token: string | null }[],
): PushTarget[] {
  const owners = new Map<string, string>();
  for (const row of deviceRows) owners.set(row.token, row.user_id);
  for (const row of legacyRows) {
    if (row.fcm_token && !owners.has(row.fcm_token)) {
      owners.set(row.fcm_token, row.id);
    }
  }
  return [...owners].flatMap(([token, userId]) => {
    const copy = copyByUserId.get(userId);
    return copy && enabledUserIds.has(userId) ? [{ userId, token, copy }] : [];
  });
}

export function buildFcmMessage(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
  badge: number,
) {
  return {
    message: {
      token,
      notification: { title, body },
      data,
      android: {
        priority: "HIGH",
        notification: {
          channel_id: ANDROID_CHANNEL_ID,
          sound: "default",
          default_vibrate_timings: true,
        },
      },
      // Badge is the recipient's real unread total, not +1, so it stays
      // correct after a missed or out-of-order push. Without `sound` iOS
      // delivers the banner silently.
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { sound: "default", badge } },
      },
    },
  };
}

export type PushResult = {
  pushSent: boolean;
  pushSkipped?: boolean;
  reason?: string;
  sentCount?: number;
  total?: number;
  clearedDeadTokens?: number;
  error?: string;
};

export async function pushToRecipients(
  admin: SupabaseClient,
  recipients: PushRecipient[],
  data: Record<string, string>,
): Promise<PushResult> {
  if (recipients.length === 0) {
    return { pushSent: false, pushSkipped: true, reason: "No new recipients" };
  }
  const serviceAccountJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!serviceAccountJson) {
    // The inbox row already landed; push is optional until Firebase is set.
    return { pushSent: false, pushSkipped: true, reason: "FCM not configured" };
  }

  const copyByUserId = new Map<string, PushRecipient>();
  for (const r of recipients) {
    if (!copyByUserId.has(r.userId)) copyByUserId.set(r.userId, r);
  }
  const { data: profiles } = await admin
    .from("profiles")
    .select("id, fcm_token")
    .in("id", [...copyByUserId.keys()])
    .eq("notifications_enabled", true);
  const enabled = (profiles ?? []) as {
    id: string;
    fcm_token: string | null;
  }[];
  const legacyTokens = enabled.flatMap((p) => p.fcm_token ? [p.fcm_token] : []);
  const [byUser, byToken] = await Promise.all([
    admin.from("device_tokens").select("user_id, token")
      .in("user_id", enabled.map((p) => p.id)),
    legacyTokens.length === 0 ? { data: [] } : admin.from("device_tokens")
      .select("user_id, token").in("token", legacyTokens),
  ]);
  const tokenOwners = pushTargets(
    copyByUserId,
    new Set(enabled.map((p) => p.id)),
    [...(byUser.data ?? []), ...(byToken.data ?? [])],
    enabled,
  );
  if (tokenOwners.length === 0) {
    return {
      pushSent: false,
      pushSkipped: true,
      reason: "No device token(s) for this audience",
    };
  }

  const serviceAccount = JSON.parse(serviceAccountJson);
  const auth = new GoogleAuth({
    credentials: serviceAccount,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const accessToken = await (await auth.getClient()).getAccessToken();
  if (!accessToken.token) {
    return { pushSent: false, error: "Could not obtain FCM access token" };
  }

  const badges = new Map(
    await Promise.all(
      [...new Set(tokenOwners.map((t) => t.userId))].map(async (userId) => {
        const { count } = await admin
          .from("notifications")
          .select("id", { count: "exact", head: true })
          .eq("user_id", userId)
          .eq("read", false)
          .is("dismissed_at", null);
        return [userId, count ?? 0] as const;
      }),
    ),
  );

  const results = await Promise.all(
    tokenOwners.map(async (t) => {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken.token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(
            buildFcmMessage(
              t.token,
              t.copy.title,
              t.copy.body,
              data,
              badges.get(t.userId) ?? 1,
            ),
          ),
        },
      );
      if (res.ok) return { token: t.token, ok: true, unregistered: false };
      const text = await res.text();
      console.error("[push] FCM send failed", res.status, text);
      // A dead token (uninstall/rotation) would otherwise be retried forever.
      return {
        token: t.token,
        ok: false,
        unregistered: text.includes("UNREGISTERED") ||
          text.includes("NOT_FOUND"),
      };
    }),
  );

  const deadTokens = results.filter((r) => r.unregistered).map((r) => r.token);
  if (deadTokens.length > 0) {
    const [devices, legacy] = await Promise.all([
      admin.from("device_tokens").delete().in("token", deadTokens),
      admin.from("profiles").update({ fcm_token: null })
        .in("fcm_token", deadTokens),
    ]);
    const error = devices.error ?? legacy.error;
    if (error) console.error("[push] failed to clear dead tokens", error);
  }
  const sentCount = results.filter((r) => r.ok).length;
  return {
    pushSent: sentCount > 0,
    sentCount,
    total: tokenOwners.length,
    clearedDeadTokens: deadTokens.length,
  };
}
