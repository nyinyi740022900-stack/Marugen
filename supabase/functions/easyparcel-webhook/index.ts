// Supabase Edge Function: easyparcel-webhook
//
// Receives EasyParcel's push notifications (Tracking Status Update /
// Shipment Status Update / Shipment AWB Update — registered in the
// Developer Hub → Marugen Koi Farm App → Webhook) and writes the latest
// status onto the matching order, same shape as track-webhook does for
// 17TRACK.
//
// Signature verification: confirmed with EasyParcel Integration Support
// (2026-09-28) that their outgoing webhooks carry NO HMAC signature,
// shared secret, or API key — there is nothing to cryptographically
// verify. Their own recommended mitigation is to allowlist their server
// IPs, which is what ALLOWED_SOURCE_IPS below does. This is weaker than a
// signature (IPs can in principle be spoofed at the network layer) but is
// what EasyParcel supports today. On top of that, this endpoint still
// only matches orders already booked through EasyParcel (by
// easyparcel_shipment_id, falling back to tracking number), which limits
// a forged call to someone who already knows a real shipment id.
//
// Deploy:  supabase functions deploy easyparcel-webhook --no-verify-jwt
// (--no-verify-jwt because EasyParcel calls this directly, not through
// the app's auth.)
// Secrets: none new.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey =
  Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

// EasyParcel's confirmed outgoing webhook server IPs (per Integration
// Support, 2026-09-28). Update this list if they add/rotate IPs.
const ALLOWED_SOURCE_IPS = new Set(['47.254.255.46', '117.53.155.92']);

function getClientIp(req: Request): string | null {
  // Supabase Edge Functions run behind a proxy that sets x-forwarded-for;
  // the first entry is the original client.
  const forwardedFor = req.headers.get('x-forwarded-for');
  if (forwardedFor) {
    const first = forwardedFor.split(',')[0]?.trim();
    if (first) return first;
  }
  return req.headers.get('x-real-ip');
}

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
    console.error('[easyparcel-webhook] notifyOrder failed', err);
  }
}

// Payload shape per the official docs (easyparcel.github.io/OpenAPI,
// "Webhooks", version 2026-06) — flat JSON, no `data` wrapper. Fields vary
// by `topic`:
//   shipment.status.update:  shipment_number, awb_number, shipment_status,
//                            shipment_status_code
//   shipment.tracking.update: shipment_number, awb_number,
//                            latest_tracking_status, latest_shipment_status_code
//   shipment.awb.update:     shipment_number, awb_number, awb_url (no status)
// `easyparcel_shipment_id` is saved from this same `shipment_number` value
// at booking time (see easyparcel-book-shipment/index.ts), so matching on
// it here lines up.
function extractFields(body: Record<string, unknown>) {
  const shipmentId = (body.shipment_number ?? null) as string | null;
  const trackingNumber = (body.awb_number ?? null) as string | null;
  const statusCode = (body.shipment_status_code ?? body.latest_shipment_status_code ?? null) as
    | number
    | null;
  const statusText = (body.shipment_status ?? body.latest_tracking_status ?? null) as
    | string
    | null;
  return { shipmentId, trackingNumber, statusCode, statusText };
}

Deno.serve(async (req) => {
  try {
    const clientIp = getClientIp(req);
    if (!clientIp || !ALLOWED_SOURCE_IPS.has(clientIp)) {
      console.error('[easyparcel-webhook] rejected request from untrusted IP', clientIp);
      return new Response(JSON.stringify({ received: false, error: 'untrusted source' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const rawBody = await req.text();
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return new Response(JSON.stringify({ received: true, error: 'invalid JSON' }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const { shipmentId, trackingNumber, statusCode, statusText } = extractFields(body);
    if (!shipmentId && !trackingNumber) {
      // Not a shape we recognise — acknowledge anyway so EasyParcel doesn't retry forever.
      return new Response(JSON.stringify({ received: true }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Only ever matches orders EasyParcel itself already booked — see the
    // signature-gap note above for why this matters.
    const patch: Record<string, unknown> = {};
    if (statusText != null || statusCode != null) {
      if (statusText != null) patch.tracking_status = statusText;
      if (statusCode != null) patch.tracking_status_code = statusCode;
      patch.tracking_updated_at = new Date().toISOString();
    }
    if (body.topic === 'shipment.awb.update') {
      if (typeof body.awb_url === 'string' && body.awb_url.trim()) {
        patch.easyparcel_awb_url = body.awb_url;
      }
      if (trackingNumber && shipmentId) patch.qxpress_tracking_no = trackingNumber;
    }
    if (Object.keys(patch).length === 0) {
      return new Response(JSON.stringify({ received: true }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }
    let query = supabaseAdmin
      .from('orders')
      .update(patch)
      .eq('tracking_provider', 'easyparcel');
    query = shipmentId
      ? query.eq('easyparcel_shipment_id', shipmentId)
      : query.eq('qxpress_tracking_no', trackingNumber!);

    const { data: updatedOrders, error } = await query.select('id, status');
    if (error) {
      console.error('[easyparcel-webhook] failed to write tracking status', error);
    }

    // Shipment Status Codes per the docs: 5 = Delivered, 6 = Returned.
    // Fall back to matching the free-text status in case EasyParcel omits
    // the code on some topics.
    const normalizedText = statusText?.toLowerCase() ?? '';
    const isDelivered = statusCode === 5 || normalizedText.includes('delivered');
    const isReturned = statusCode === 6 || normalizedText.includes('return');
    const isOutForDelivery = normalizedText.includes('out for delivery');

    // Mirrors track-webhook: only ever shipped → delivered, never
    // overrides cancelled/refunded/other admin-set states, no-op if
    // already delivered by some other path.
    if (isDelivered && updatedOrders) {
      for (const order of updatedOrders) {
        if (order.status !== 'shipped') continue;
        const { error: statusError } = await supabaseAdmin
          .from('orders')
          .update({ status: 'delivered' })
          .eq('id', order.id)
          .eq('status', 'shipped');
        if (statusError) {
          console.error('[easyparcel-webhook] failed to mark delivered', order.id, statusError);
          continue;
        }
        await notifyOrder(order.id, { status: 'delivered' });
      }
    }

    if (isOutForDelivery && updatedOrders) {
      for (const order of updatedOrders) {
        if (order.status !== 'shipped') continue;
        await notifyOrder(order.id, { event: 'out_for_delivery' });
      }
    }

    // Courier-reported return — admin-only alert, never an automatic
    // status change (see file header / send-order-notification's
    // shipment_returned copy for why).
    if (isReturned && updatedOrders) {
      for (const order of updatedOrders) {
        await notifyOrder(order.id, { event: 'shipment_returned' });
      }
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('[easyparcel-webhook] error', err);
    return new Response(JSON.stringify({ received: true, error: `${err}` }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
