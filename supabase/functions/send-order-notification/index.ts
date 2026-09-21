// Supabase Edge Function: send-order-notification
//
// Records an in-app notification (public.notifications, see
// 0016_notifications.sql) for the relevant recipient(s), and — best
// effort, only if configured — also sends it as a push via Firebase Cloud
// Messaging (HTTP v1 API). The in-app inbox write always happens, even
// with zero Firebase setup: that's what makes the Notifications screen
// (both customer and admin) work from day one, independent of whether
// push delivery itself is live yet. The client half
// (lib/core/notifications/push_notification_service.dart) registers each
// device's FCM token onto `profiles.fcm_token` (0003_fcm_token.sql) and is
// fully wired to *receive* pushes; this is the server-side half that
// actually sends one, when it can.
//
// Two request shapes, two audiences:
//   1. { order_id, status } — one of paid/shipped/delivered/cancelled.
//      Notifies the order's own customer.
//   2. { order_id, event: 'out_for_delivery' } — notifies every admin
//      (profiles.role in ('staff','owner')), so staff know a courier
//      delivery is imminent without watching the Fulfillment tab. Fired
//      from track-webhook when 17TRACK reports the courier's
//      "OutForDelivery" status. Never fires for live-fish orders — those
//      never get a qxpress_tracking_no, so 17TRACK never has anything to
//      report for them in the first place; admin already handles those
//      manually via "Delivered by shop".
//
// Who calls this:
//   - stripe-webhook, right after marking an order `paid`.
//   - track-webhook, right after 17TRACK reports `Delivered` (flips the
//     order to `delivered`) or `OutForDelivery` (admin alert only, no
//     order status change).
//   - OrderRepository.updateOrderStatus (lib/features/orders/data/
//     order_repository.dart), fire-and-forget, right after any admin
//     status change (shipped/delivered/cancelled) — this call carries the
//     admin's own session JWT, so it *is* admin-checked below.
//   All of the above are either service-role-to-service-role (trusted, no
//   further check needed) or an authenticated admin session (checked
//   below) — see `isServiceRoleCaller`.
//
// Deploy:  supabase functions deploy send-order-notification
// Secrets: supabase secrets set FCM_SERVICE_ACCOUNT_JSON='<firebase service account JSON>'
//   (Firebase Console → Project Settings → Service Accounts → Generate new
//   private key. Same Firebase project as GoogleService-Info.plist /
//   google-services.json.) — optional; the in-app inbox works without it.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { GoogleAuth } from 'https://esm.sh/google-auth-library@9?target=deno';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const STATUS_COPY: Record<string, { title: string; body: (orderShort: string) => string }> = {
  paid: {
    title: 'Order confirmed',
    body: (id) => `We've received payment for order #${id}. We'll start packing it soon.`,
  },
  shipped: {
    title: 'Order shipped',
    body: (id) => `Order #${id} is on its way.`,
  },
  delivered: {
    title: 'Order delivered',
    body: (id) => `Order #${id} has been delivered. Enjoy!`,
  },
  cancelled: {
    title: 'Order cancelled',
    body: (id) => `Order #${id} was cancelled.`,
  },
};

const EVENT_COPY: Record<string, { title: string; body: (orderShort: string) => string }> = {
  out_for_delivery: {
    title: 'Out for delivery',
    body: (id) => `Order #${id} is out for delivery today.`,
  },
};

/// Gets an OAuth access token for the FCM HTTP v1 API from a Firebase
/// service account, then sends one notification to one device token.
/// Returns the FCM response status so callers can log/aggregate failures
/// without this function ever throwing over a delivery problem.
async function sendPush(
  serviceAccount: { project_id: string },
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; error?: string; unregistered?: boolean }> {
  const fcmRes = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message: { token, notification: { title, body }, data } }),
    },
  );
  if (!fcmRes.ok) {
    const text = await fcmRes.text();
    console.error('[send-order-notification] FCM send failed', fcmRes.status, text);
    // FCM's HTTP v1 API reports a dead token as UNREGISTERED (uninstalled/
    // token rotated) — without checking this, a dead token stays in
    // profiles.fcm_token forever and every future notification keeps
    // retrying delivery to it for no reason.
    const isUnregistered = text.includes('UNREGISTERED') || text.includes('NOT_FOUND');
    return { ok: false, error: text, unregistered: isUnregistered };
  }
  return { ok: true };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { order_id, status, event } = await req.json();
    const statusCopy = status ? STATUS_COPY[status as string] : undefined;
    const eventCopy = event ? EVENT_COPY[event as string] : undefined;
    if (!order_id || (!statusCopy && !eventCopy)) {
      return jsonResponse({ skipped: true, reason: 'Unsupported status/event' });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    // Prefer the new secret key (set explicitly via `supabase secrets set`)
    // over the legacy JWT service_role name the platform auto-injects —
    // stripe-webhook/track-webhook resolve their own serviceRoleKey the
    // same way when calling this function, so the two stay in sync.
    const serviceKey =
      Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const admin = createClient(supabaseUrl, serviceKey);

    // Caller must be either another edge function using the service-role
    // key (stripe-webhook/track-webhook — trusted, order state already
    // verified there) or an admin's own session (the Flutter admin app
    // calling this after updateOrderStatus). Reject anyone else so a
    // logged-in customer can't use this endpoint to push arbitrary
    // notifications.
    const authHeader = req.headers.get('Authorization') ?? '';
    // Exact match, not a substring check — `includes` would also pass for
    // any header that merely contains the key as a prefix/suffix of a
    // longer forged value.
    const isServiceRoleCaller = serviceKey.length > 0 && authHeader === `Bearer ${serviceKey}`;
    if (!isServiceRoleCaller) {
      const anonKey = Deno.env.get('SB_ANON_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? '';
      const userClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authHeader } },
      });
      const {
        data: { user },
        error: userError,
      } = await userClient.auth.getUser();
      if (userError || !user) {
        return jsonResponse({ error: 'Unauthorized' }, 401);
      }
      // Same admin check as track-register/index.ts: `profiles.role` is
      // 'staff' or 'owner' for admins in this app (see is_admin() in
      // 0001_init.sql), never the string 'admin'.
      const { data: profile } = await admin
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
      if (profile?.role !== 'staff' && profile?.role !== 'owner') {
        return jsonResponse({ error: 'Forbidden' }, 403);
      }
    }

    const { data: order } = await admin
      .from('orders')
      .select('id, user_id')
      .eq('id', order_id)
      .maybeSingle();
    if (!order) {
      return jsonResponse({ skipped: true, reason: 'Order not found' });
    }
    const orderShort = (order.id as string).slice(0, 8);

    // Resolve the recipient user id(s) for this request's audience —
    // independent of whether they have an fcm_token, since the in-app
    // inbox row below doesn't need one.
    let recipientIds: string[];
    if (eventCopy) {
      // Admin alert — every staff/owner.
      const { data: admins } = await admin.from('profiles').select('id').in('role', [
        'staff',
        'owner',
      ]);
      recipientIds = (admins ?? []).map((p) => p.id as string);
    } else {
      // Customer notification — the order's own owner.
      recipientIds = [order.user_id as string];
    }

    if (recipientIds.length === 0) {
      return jsonResponse({ skipped: true, reason: 'No recipients for this audience' });
    }

    const copy = (statusCopy ?? eventCopy)!;
    const title = copy.title;
    const body = copy.body(orderShort);

    // Always write the in-app inbox row — this is what makes the
    // Notifications screen work with zero Firebase setup. Best-effort:
    // logged, not fatal, since a push might still go out below even if
    // this insert somehow fails.
    //
    // Upserts on (order_id, user_id, key) with ignoreDuplicates so a
    // retried call (network retry, or 17TRACK/Stripe redelivering the
    // same webhook event) is a no-op instead of a second inbox row + a
    // second push — see 0029_notification_idempotency.sql. PostgREST's
    // ON CONFLICT DO NOTHING only returns rows that were actually
    // inserted, so `inserted` below is exactly "genuinely new this call".
    const notificationKey = status ?? event!;
    const { data: inserted, error: insertError } = await admin
      .from('notifications')
      .upsert(
        recipientIds.map((userId) => ({
          user_id: userId,
          title,
          body,
          order_id: order.id,
          type: eventCopy ? 'admin_alert' : 'order_status',
          key: notificationKey,
        })),
        { onConflict: 'order_id,user_id,key', ignoreDuplicates: true },
      )
      .select('user_id');
    if (insertError) {
      console.error('[send-order-notification] failed to write inbox rows', insertError);
    }
    // Only push to recipients who just got a genuinely new row above —
    // someone already notified for this order+key on an earlier call
    // shouldn't get a second push just because this call retried.
    const newlyNotifiedIds = new Set((inserted ?? []).map((r) => r.user_id as string));

    if (newlyNotifiedIds.size === 0) {
      // Every recipient already had this exact (order_id, user_id, key)
      // row — a pure retry of an already-handled event. Nothing left to do.
      return jsonResponse({ inboxWritten: false, pushSkipped: true, reason: 'Already notified (duplicate)' });
    }

    // Push delivery is optional on top of the inbox write above.
    const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    if (!serviceAccountJson) {
      // Not configured yet — expected until a real Firebase project
      // exists. Not an error: the in-app inbox row above already landed.
      return jsonResponse({ inboxWritten: !insertError, pushSkipped: true, reason: 'FCM not configured' });
    }

    const { data: recipients } = await admin
      .from('profiles')
      .select('id, fcm_token')
      .in('id', [...newlyNotifiedIds])
      .not('fcm_token', 'is', null)
      .eq('notifications_enabled', true);
    const tokenOwners = (recipients ?? [])
      .filter((p) => p.fcm_token)
      .map((p) => ({ userId: p.id as string, token: p.fcm_token as string }));
    const tokens = tokenOwners.map((t) => t.token);

    if (tokens.length === 0) {
      return jsonResponse({
        inboxWritten: !insertError,
        pushSkipped: true,
        reason: 'No device token(s) for this audience',
      });
    }

    const serviceAccount = JSON.parse(serviceAccountJson);
    const auth = new GoogleAuth({
      credentials: serviceAccount,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });
    const client = await auth.getClient();
    const accessToken = await client.getAccessToken();
    if (!accessToken.token) {
      return jsonResponse({
        inboxWritten: !insertError,
        pushSent: false,
        error: 'Could not obtain FCM access token',
      });
    }

    const data = { order_id: order.id, ...(status ? { status } : {}), ...(event ? { event } : {}) };
    const results = await Promise.all(
      tokenOwners.map((t) =>
        sendPush(serviceAccount, accessToken.token!, t.token, title, body, data).then((r) => ({
          ...r,
          userId: t.userId,
        })),
      ),
    );
    const sentCount = results.filter((r) => r.ok).length;

    // Clear any token FCM reported as dead — otherwise it stays in
    // profiles.fcm_token forever and every future notification keeps
    // retrying delivery to it for nothing.
    const deadOwnerIds = results.filter((r) => r.unregistered).map((r) => r.userId);
    if (deadOwnerIds.length > 0) {
      const { error: clearError } = await admin
        .from('profiles')
        .update({ fcm_token: null })
        .in('id', deadOwnerIds);
      if (clearError) {
        console.error('[send-order-notification] failed to clear dead tokens', clearError);
      }
    }

    // Don't fail the caller's request over a push-delivery problem (e.g. a
    // stale/unregistered token) — the order state change itself already
    // succeeded, and the inbox row above already landed regardless.
    return jsonResponse({
      inboxWritten: !insertError,
      pushSent: sentCount > 0,
      sentCount,
      total: tokens.length,
      clearedDeadTokens: deadOwnerIds.length,
    });
  } catch (err) {
    console.error('[send-order-notification] error', err);
    // Same reasoning as above: never let a notification failure look like
    // an order-processing failure to the caller.
    return jsonResponse({ sent: false, error: `${err}` });
  }
});
