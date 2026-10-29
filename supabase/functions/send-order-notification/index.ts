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
import { pushToRecipients } from '../_shared/push.ts';

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
  packing: {
    title: 'Order packing',
    body: (id) => `We're packing order #${id} now.`,
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
  // Fired by the new stripe-refund Edge Function once a real Stripe
  // refund has been issued — this is a genuine customer-facing money
  // event now, unlike before when "refunded" was just a status label.
  refunded: {
    title: 'Order refunded',
    body: (id) => `Order #${id} has been refunded to your original payment method.`,
  },
};

const EVENT_COPY: Record<string, { title: string; body: (orderShort: string) => string }> = {
  out_for_delivery: {
    title: 'Out for delivery',
    body: (id) => `Order #${id} is out for delivery today.`,
  },
  // Fired by easyparcel-webhook on a courier-reported return — admin-only
  // alert, no automatic order.status change (there's no "returned" status;
  // whether to cancel/refund/re-ship is an admin judgment call).
  shipment_returned: {
    title: 'Shipment returned',
    body: (id) => `The courier is returning order #${id}'s shipment to the shop.`,
  },
};

const ADMIN_NEW_ORDER_COPY = {
  title: 'New order',
  body: (id: string) => `New order #${id} just came in — payment received.`,
};

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
      .select('id, user_id, order_number')
      .eq('id', order_id)
      .maybeSingle();
    if (!order) {
      return jsonResponse({ skipped: true, reason: 'Order not found' });
    }
    const orderShort = order.order_number || (order.id as string).slice(0, 8);

    // Resolve the audience "targets" for this request — each with its own
    // recipient ids, title and body, and its own inbox `type`. Independent
    // of whether recipients have an fcm_token, since the in-app inbox row
    // below doesn't need one.
    //
    // A `paid` order gets two targets: the customer ("Order confirmed")
    // and, separately, every admin ("New order" — so staff/owner see a new
    // paid order land without watching the dashboard). Every other
    // status/event has exactly one target, as before.
    type Target = { recipientIds: string[]; title: string; body: string; type: string };
    const targets: Target[] = [];

    if (eventCopy) {
      // Admin alert — every staff/owner.
      const { data: admins } = await admin.from('profiles').select('id').in('role', [
        'staff',
        'owner',
      ]);
      targets.push({
        recipientIds: (admins ?? []).map((p) => p.id as string),
        title: eventCopy.title,
        body: eventCopy.body(orderShort),
        type: 'admin_alert',
      });
    } else {
      // Customer notification — the order's own owner.
      targets.push({
        recipientIds: order.user_id ? [order.user_id as string] : [],
        title: statusCopy!.title,
        body: statusCopy!.body(orderShort),
        type: 'order_status',
      });

      if (status === 'paid') {
        const { data: admins } = await admin.from('profiles').select('id').in('role', [
          'staff',
          'owner',
        ]);
        const adminIds = (admins ?? []).map((p) => p.id as string);
        if (adminIds.length > 0) {
          targets.push({
            recipientIds: adminIds,
            title: ADMIN_NEW_ORDER_COPY.title,
            body: ADMIN_NEW_ORDER_COPY.body(orderShort),
            type: 'admin_alert',
          });
        }
      }
    }

    const nonEmptyTargets = targets.filter((t) => t.recipientIds.length > 0);
    if (nonEmptyTargets.length === 0) {
      return jsonResponse({ skipped: true, reason: 'No recipients for this audience' });
    }

    const notificationKey = status ?? event!;

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
    // Customer and admin rows share the same key but never the same
    // user_id, so the two targets never collide on the conflict target.
    const { data: inserted, error: insertError } = await admin
      .from('notifications')
      .upsert(
        nonEmptyTargets.flatMap((t) =>
          t.recipientIds.map((userId) => ({
            user_id: userId,
            title: t.title,
            body: t.body,
            order_id: order.id,
            type: t.type,
            key: notificationKey,
          })),
        ),
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

    // Push only to recipients with a genuinely new inbox row above.
    const pushRecipients = nonEmptyTargets.flatMap((t) =>
      t.recipientIds
        .filter((userId) => newlyNotifiedIds.has(userId))
        .map((userId) => ({ userId, title: t.title, body: t.body })),
    );
    const data = { order_id: order.id, ...(status ? { status } : {}), ...(event ? { event } : {}) };
    // Never fail the caller over push delivery: the order change and the
    // inbox row already succeeded.
    const push = await pushToRecipients(admin, pushRecipients, data);
    return jsonResponse({ inboxWritten: !insertError, ...push });
  } catch (err) {
    console.error('[send-order-notification] error', err);
    // Same reasoning as above: never let a notification failure look like
    // an order-processing failure to the caller.
    return jsonResponse({ sent: false, error: `${err}` });
  }
});
