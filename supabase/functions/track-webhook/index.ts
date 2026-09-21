// Supabase Edge Function: track-webhook
//
// Receives push notifications from 17TRACK whenever a registered tracking
// number's status changes, and writes the latest status onto the matching
// order. This is the "Package Webhook" URL you paste into 17TRACK's
// dashboard (Settings → Package Webhook → URL).
//
// Deploy:  supabase functions deploy track-webhook --no-verify-jwt
// (--no-verify-jwt because 17TRACK calls this directly, not through your app's auth
// — signature verification below is what replaces JWT auth for this endpoint)
// Secrets: none new — reuses TRACK17_API_KEY (already set for track-register).
//          17TRACK's webhook signature is keyed with your account's API
//          Security Key (Settings → Security → Key in the 17TRACK
//          dashboard), the same value used as the `17token` header
//          everywhere else — there is no separate "webhook secret".
//
// 17TRACK's push payload shape (v2.x):
// { "event": "TRACKING_UPDATED", "data": { "number": "...", "carrier": 100001,
//   "track_info": { "latest_status": { "status": "...", "sub_status": "..." },
//                    "latest_event": { "description": "...", "time_iso": "..." } } } }
//
// Signature: 17TRACK sends a `sign` header computed as
// SHA256(raw_json_body + "/" + api_security_key), hex-encoded — see
// https://api.17track.net/en/doc#Webhook ("Create and Verify the
// Signature"). Without checking this, anyone who learns/guesses a
// tracking number could POST a forged "Delivered" event here and flip a
// real order's status (order lifecycle is customer-visible and used to
// decide when a live-fish order is closed out) — see the P1 finding this
// fixes.
//
// Auto-advancing the order to `delivered`, and alerting admin on
// `OutForDelivery`: both only ever apply to courier-tracked orders
// (they're the only ones with a qxpress_tracking_no in the first place).
// Live fish never go through a courier/17TRACK at all — admin closes those
// out with the "Delivered by shop" action in the admin Delivery screen
// instead (see delivery_repository.dart), so there is nothing for this
// webhook to react to for them.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
// Prefer the new secret key (set explicitly via `supabase secrets set`)
// over the legacy JWT service_role name the platform auto-injects, so
// this keeps working whether or not legacy JWT-based API keys are later
// disabled project-wide.
const serviceRoleKey =
  Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const track17ApiKey = Deno.env.get('TRACK17_API_KEY') ?? '';

const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function isValidSignature(rawBody: string, signature: string | null): Promise<boolean> {
  if (!track17ApiKey || !signature) return false;
  const expected = await sha256Hex(`${rawBody}/${track17ApiKey}`);
  // Constant-time-ish compare: both are fixed 64-char hex, so this loop
  // doesn't leak more than a real timing-safe compare would here.
  if (expected.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ signature.toLowerCase().charCodeAt(i);
  }
  return mismatch === 0;
}

// Best-effort push notification — see send-order-notification for the
// full explanation (including the `status` vs `event` request shapes).
// Never allowed to fail this webhook's response back to 17TRACK (which
// otherwise retries indefinitely on a non-200).
async function notifyOrder(orderId: string, payload: { status?: string; event?: string }) {
  try {
    await fetch(`${supabaseUrl}/functions/v1/send-order-notification`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ order_id: orderId, ...payload }),
    });
  } catch (err) {
    console.error('[track-webhook] notifyOrder failed', err);
  }
}

Deno.serve(async (req) => {
  try {
    const rawBody = await req.text();
    const signature = req.headers.get('sign');
    if (!(await isValidSignature(rawBody, signature))) {
      console.error('[track-webhook] rejected: invalid or missing signature');
      // Still 200 so 17TRACK doesn't retry a request that will never pass —
      // but the write below never happens without a valid signature.
      return new Response(JSON.stringify({ received: false, error: 'invalid signature' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const body = JSON.parse(rawBody);
    const data = body?.data;
    const number: string | undefined = data?.number;
    if (!number) {
      // Not a shape we recognise — acknowledge anyway so 17TRACK doesn't retry forever.
      return new Response(JSON.stringify({ received: true }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const status: string | undefined = data?.track_info?.latest_status?.status;
    const eventDescription: string | undefined = data?.track_info?.latest_event?.description;

    // .select() so we know which order(s) matched and their current
    // status — needed below to decide whether this is a genuine
    // shipped→delivered transition, not just to log the write.
    const { data: updatedOrders, error } = await supabaseAdmin
      .from('orders')
      .update({
        tracking_status: status ?? null,
        tracking_status_detail: eventDescription ?? null,
        tracking_updated_at: new Date().toISOString(),
      })
      .eq('qxpress_tracking_no', number)
      .select('id, status');

    if (error) {
      console.error('[track-webhook] failed to write tracking status', number, error);
    }

    // 17TRACK's terminal "delivered" status (v2.x: track_info.latest_status.status
    // = "Delivered") is the carrier confirming the parcel was handed over —
    // advance the order's own lifecycle status to match, the same way
    // track-register already advances it to `shipped` when the tracking
    // number is first registered. Only ever moves `shipped` → `delivered`:
    // never overrides a `cancelled`/`refunded`/other state an admin may
    // have set for other reasons, and is a no-op if the order was already
    // delivered by some other path.
    if (status?.toLowerCase() === 'delivered' && updatedOrders) {
      for (const order of updatedOrders) {
        if (order.status !== 'shipped') continue;
        const { error: statusError } = await supabaseAdmin
          .from('orders')
          .update({ status: 'delivered' })
          .eq('id', order.id)
          .eq('status', 'shipped');
        if (statusError) {
          console.error('[track-webhook] failed to mark delivered', order.id, statusError);
          continue;
        }
        await notifyOrder(order.id, { status: 'delivered' });
      }
    }

    // "OutForDelivery" doesn't change the order's own status (it's still
    // meaningfully `shipped` — see the file header) but is worth an
    // immediate heads-up to admin so staff know a delivery is imminent
    // without polling the Fulfillment tab. Matched loosely
    // (case/space-insensitive) since carriers vary in exact casing.
    if (status?.toLowerCase().replace(/\s+/g, '') === 'outfordelivery' && updatedOrders) {
      for (const order of updatedOrders) {
        if (order.status !== 'shipped') continue;
        await notifyOrder(order.id, { event: 'out_for_delivery' });
      }
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    // Still 200 — a malformed payload shouldn't make 17TRACK hammer retries.
    console.error('[track-webhook] error', err);
    return new Response(JSON.stringify({ received: true, error: `${err}` }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
