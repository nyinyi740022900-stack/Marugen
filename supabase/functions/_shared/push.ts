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
    .not("fcm_token", "is", null)
    .eq("notifications_enabled", true);
  const tokenOwners = (profiles ?? [])
    .filter((p) => p.fcm_token)
    .map((p) => ({
      userId: p.id as string,
      token: p.fcm_token as string,
      copy: copyByUserId.get(p.id as string)!,
    }));
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
      tokenOwners.map(async (t) => {
        const { count } = await admin
          .from("notifications")
          .select("id", { count: "exact", head: true })
          .eq("user_id", t.userId)
          .eq("read", false)
          .is("dismissed_at", null);
        return [t.userId, count ?? 0] as const;
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
      if (res.ok) return { userId: t.userId, ok: true, unregistered: false };
      const text = await res.text();
      console.error("[push] FCM send failed", res.status, text);
      // A dead token (uninstall/rotation) would otherwise be retried forever.
      return {
        userId: t.userId,
        ok: false,
        unregistered: text.includes("UNREGISTERED") ||
          text.includes("NOT_FOUND"),
      };
    }),
  );

  const deadOwnerIds = results.filter((r) => r.unregistered).map((r) =>
    r.userId
  );
  if (deadOwnerIds.length > 0) {
    const { error } = await admin
      .from("profiles")
      .update({ fcm_token: null })
      .in("id", deadOwnerIds);
    if (error) console.error("[push] failed to clear dead tokens", error);
  }
  const sentCount = results.filter((r) => r.ok).length;
  return {
    pushSent: sentCount > 0,
    sentCount,
    total: tokenOwners.length,
    clearedDeadTokens: deadOwnerIds.length,
  };
}
