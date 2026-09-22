// Supabase Edge Function: easyparcel-refresh-status
//
// On-demand pull of an EasyParcel shipment's current status (pickup,
// in-transit, delivered, returned, ...) via EasyParcel's own Tracking
// Status API — the EasyParcel equivalent of track-status for 17TRACK.
// Lets the customer/admin "Refresh tracking" button on an EasyParcel-booked
// order show real progress instead of only ever reading the static
// "Booked" text easyparcel-book-shipment wrote at booking time, since
// easyparcel-webhook's own push has an unverified signature (see its file
// header) and the sandbox environment doesn't push status changes at all
// (see EasyParcel's Sandbox Limitations docs) — this pull path works in
// both.
//
// Status codes per https://easyparcel.github.io/OpenAPI/ "Shipment Status
// Codes": 0 Cancel, 2 To Be Collected, 3 Collected (picked up), 4 Delivery
// In Transit, 5 Delivered, 6 Returned, 7 Schedule In Arrangement, 8 On
// Hold, 11 Drop Off.
//
// Deploy:  supabase functions deploy easyparcel-refresh-status
// Secrets: EASYPARCEL_CLIENT_ID / EASYPARCEL_CLIENT_SECRET (already set)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getEasyParcelAccessToken, EasyParcelNotConnectedError } from '../_shared/easyparcel_token.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SB_ANON_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceRoleKey =
  Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonError(message: string, status: number) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function notifyOrder(admin: ReturnType<typeof createClient>, orderId: string, payload: { status?: string; event?: string }) {
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
    console.error('[easyparcel-refresh-status] notifyOrder failed', err);
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonError('Missing Authorization header', 401);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) return jsonError('Unauthorized', 401);

    const { order_id } = await req.json();
    if (!order_id) return jsonError('order_id is required', 400);

    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Only the order's own customer or an admin may pull its status —
    // same rule as track-status.
    const { data: order } = await admin
      .from('orders')
      .select('id, status, user_id, tracking_provider, qxpress_tracking_no')
      .eq('id', order_id)
      .maybeSingle();
    if (!order) return jsonError('Order not found', 404);

    if (order.user_id !== user.id) {
      const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle();
      if (!profile || (profile.role !== 'staff' && profile.role !== 'owner')) {
        return jsonError('Not authorized to view this order', 403);
      }
    }

    if (order.tracking_provider !== 'easyparcel') {
      return jsonError('This order is not tracked via EasyParcel', 400);
    }
    if (!order.qxpress_tracking_no) return jsonError('This order has no tracking number yet', 400);

    let accessToken: string;
    try {
      accessToken = await getEasyParcelAccessToken(admin);
    } catch (err) {
      if (err instanceof EasyParcelNotConnectedError) return jsonError(err.message, 409);
      throw err;
    }

    const trackRes = await fetch(
      'https://api.easyparcel.com/open_api/2026-06/shipment/tracking_status',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ awb_numbers: [order.qxpress_tracking_no] }),
      },
    );
    const trackData = await trackRes.json();
    if (!trackRes.ok || (trackData?.status_code && trackData.status_code !== 200)) {
      console.error('[easyparcel-refresh-status] tracking_status failed', trackRes.status, JSON.stringify(trackData));
      return jsonError(
        trackData?.message ? `EasyParcel: ${trackData.message}` : `Could not fetch tracking status (${trackRes.status})`,
        502,
      );
    }

    const result = trackData?.data?.results?.[0];
    if (!result || result.status !== 'success') {
      return jsonError('EasyParcel: no tracking data for this shipment yet', 502);
    }

    const statusCode: number | undefined = result.latest_shipment_status_code;
    const statusText: string | undefined = result.latest_tracking_status;
    const location: string | null = result.status_log?.[0]?.location ?? null;

    await admin
      .from('orders')
      .update({
        tracking_status: statusText ?? null,
        tracking_status_detail: location,
        tracking_status_code: statusCode ?? null,
        tracking_updated_at: new Date().toISOString(),
      })
      .eq('id', order_id);

    // Mirrors easyparcel-webhook: only ever shipped → delivered, and a
    // return is an admin-alert only, never an automatic status change.
    if (statusCode === 5 && order.status === 'shipped') {
      const { error: statusError } = await admin
        .from('orders')
        .update({ status: 'delivered' })
        .eq('id', order_id)
        .eq('status', 'shipped');
      if (!statusError) {
        await notifyOrder(admin, order_id, { status: 'delivered' });
      }
    } else if (statusCode === 6) {
      await notifyOrder(admin, order_id, { event: 'shipment_returned' });
    }

    return new Response(
      JSON.stringify({ status: statusText ?? null, detail: location }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});
