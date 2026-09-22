// Supabase Edge Function: easyparcel-webhook
//
// Receives EasyParcel's push notifications (Tracking Status Update /
// Shipment Status Update / Shipment AWB Update — registered in the
// Developer Hub → Marugen Koi Farm App → Webhook) and writes the latest
// status onto the matching order, same shape as track-webhook does for
// 17TRACK.
//
// ⚠️ KNOWN GAP — signature verification: unlike track-webhook (which
// verifies 17TRACK's `sign` header, SHA256(body + "/" + api_key)),
// EasyParcel's Open API docs (https://easyparcel.github.io/OpenAPI/) do
// not document a signature header/algorithm, and the Developer Hub's
// webhook UI doesn't surface a per-endpoint signing secret either. This
// endpoint currently has NO cryptographic verification that a request
// really came from EasyParcel — it only requires the payload to reference
// an order that's already been booked through EasyParcel (matched by
// easyparcel_shipment_id, falling back to the tracking number), which
// limits a forged call to someone who already knows a real shipment id
// for a real order. Follow up with EasyParcel support (api@easyparcel.com)
// to get the real verification method and tighten this — don't treat the
// current state as secure.
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

// EasyParcel's exact payload shape isn't pinned down from static docs —
// read defensively across the field-name variants the Open API reference
// mentions (tracking_number/awb_no, shipment_id/order_no, status/event).
function extractFields(body: Record<string, unknown>) {
  const data = (body.data as Record<string, unknown>) ?? body;
  const shipmentId = (data.shipment_id ?? data.order_no ?? null) as string | null;
  const trackingNumber = (data.tracking_number ?? data.awb_no ?? null) as string | null;
  const status = (data.status ?? data.tracking_status ?? null) as string | null;
  const statusDetail = (data.status_detail ?? data.description ?? null) as string | null;
  return { shipmentId, trackingNumber, status, statusDetail };
}

Deno.serve(async (req) => {
  try {
    const rawBody = await req.text();
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return new Response(JSON.stringify({ received: true, error: 'invalid JSON' }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const { shipmentId, trackingNumber, status, statusDetail } = extractFields(body);
    if (!shipmentId && !trackingNumber) {
      // Not a shape we recognise — acknowledge anyway so EasyParcel doesn't retry forever.
      return new Response(JSON.stringify({ received: true }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Only ever matches orders EasyParcel itself already booked — see the
    // signature-gap note above for why this matters.
    let query = supabaseAdmin
      .from('orders')
      .update({
        tracking_status: status ?? null,
        tracking_status_detail: statusDetail ?? null,
        tracking_updated_at: new Date().toISOString(),
      })
      .eq('tracking_provider', 'easyparcel');
    query = shipmentId
      ? query.eq('easyparcel_shipment_id', shipmentId)
      : query.eq('qxpress_tracking_no', trackingNumber!);

    const { data: updatedOrders, error } = await query.select('id, status');
    if (error) {
      console.error('[easyparcel-webhook] failed to write tracking status', error);
    }

    const normalized = status?.toLowerCase().replace(/\s+/g, '') ?? '';

    // Mirrors track-webhook: only ever shipped → delivered, never
    // overrides cancelled/refunded/other admin-set states, no-op if
    // already delivered by some other path.
    if (normalized === 'delivered' && updatedOrders) {
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

    if (normalized === 'outfordelivery' && updatedOrders) {
      for (const order of updatedOrders) {
        if (order.status !== 'shipped') continue;
        await notifyOrder(order.id, { event: 'out_for_delivery' });
      }
    }

    // Courier-reported return — admin-only alert, never an automatic
    // status change (see file header / send-order-notification's
    // shipment_returned copy for why).
    if (normalized.includes('return') && updatedOrders) {
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
