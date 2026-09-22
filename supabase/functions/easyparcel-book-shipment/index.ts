// Supabase Edge Function: easyparcel-book-shipment
//
// Admin-only. Given an order_id and the service_id/courier_id the admin
// picked from easyparcel-get-rates, books the shipment with EasyParcel,
// then writes the returned tracking number/AWB onto the order — mirroring
// exactly what track-register does for the manual/17TRACK path, so the
// existing tracking UI (admin_delivery_screen.dart, order_detail_screen.dart)
// needs no changes: tracking_provider is the only new signal.
//
// Field names below follow https://easyparcel.github.io/OpenAPI/
// ("Submit Orders") as fetched during planning — re-verify against a real
// sandbox response if EasyParcel returns a 4xx here.
//
// Deploy:  supabase functions deploy easyparcel-book-shipment
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

// Best-effort push, same pattern as track-register's callers — this
// function itself doesn't notify (track-register doesn't either; the
// customer sees the status via the order timeline). Kept for parity if a
// future "shipment booked" notification is wanted.
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
    console.error('[easyparcel-book-shipment] notifyOrder failed', err);
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

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: profile } = await admin
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
    if (!profile || (profile.role !== 'staff' && profile.role !== 'owner')) {
      return jsonError('Admin access required', 403);
    }

    const { order_id, service_id, courier_id } = await req.json();
    if (!order_id || !service_id) {
      return jsonError('order_id and service_id are required', 400);
    }

    const { data: order } = await admin
      .from('orders')
      .select('id, status, total, shipping_address')
      .eq('id', order_id)
      .maybeSingle();
    if (!order) return jsonError('Order not found', 404);
    const shipping = order.shipping_address as Record<string, unknown> | null;
    if (!shipping) return jsonError('Order has no shipping address', 400);

    const { data: settings } = await admin
      .from('settings')
      .select(
        'shop_name, shop_phone, shop_address, shop_postcode, shop_city, shop_state, shop_country, default_parcel_weight_kg',
      )
      .eq('id', 1)
      .maybeSingle();
    if (!settings?.shop_postcode) {
      return jsonError('Sender postcode is not set — fill it in under Settings first', 400);
    }

    let accessToken: string;
    try {
      accessToken = await getEasyParcelAccessToken(admin);
    } catch (err) {
      if (err instanceof EasyParcelNotConnectedError) return jsonError(err.message, 409);
      throw err;
    }

    // Per the live docs (https://easyparcel.github.io/OpenAPI/ — "Submit
    // Orders"), the endpoint is shipment/submit_orders (not
    // shipment/submit), and each shipment item needs collection_date,
    // weight/height/length/width, a non-empty item[] array, and full
    // sender/receiver objects (name/phone_number_country_code/phone_number/
    // address_1/postcode/city/subdivision_code/country_code) — a much
    // richer shape than the flat {sender,receiver,parcel} this used to
    // send, which is why booking would have failed the same way the
    // quotation call did before that was fixed.
    const collectionDate = new Date(Date.now() + 24 * 60 * 60 * 1000)
      .toISOString()
      .slice(0, 10);
    const weight = settings.default_parcel_weight_kg ?? 1;

    const submitRes = await fetch(
      'https://api.easyparcel.com/open_api/2026-06/shipment/submit_orders',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          shipment: [
            {
              reference: order_id,
              service_id,
              collection_date: collectionDate,
              weight,
              height: 5,
              length: 5,
              width: 5,
              item: [
                {
                  content: `Order ${order_id}`,
                  weight,
                  height: 5,
                  length: 5,
                  width: 5,
                  currency_code: 'SGD',
                  value: order.total ?? 0,
                  quantity: 1,
                },
              ],
              sender: {
                name: settings.shop_name,
                phone_number_country_code: 'SG',
                phone_number: settings.shop_phone ?? '',
                address_1: settings.shop_address ?? '',
                postcode: settings.shop_postcode,
                city: settings.shop_city ?? '',
                subdivision_code: settings.shop_state ?? '',
                country_code: settings.shop_country ?? 'SG',
              },
              receiver: {
                name: shipping.recipient_name,
                phone_number_country_code: 'SG',
                phone_number: shipping.phone,
                address_1: shipping.line1,
                address_2: shipping.line2 ?? '',
                postcode: shipping.postal_code,
                city: shipping.city ?? '',
                subdivision_code: '',
                country_code: 'SG',
              },
            },
          ],
        }),
      },
    );
    const submitData = await submitRes.json();
    // EasyParcel encodes success/failure in the body's own status_code
    // (HTTP status alone can be 200 with an error message inside) — see
    // easyparcel-get-rates for the same gotcha found while testing.
    if (!submitRes.ok || (submitData?.status_code && submitData.status_code !== 200)) {
      console.error('[easyparcel-book-shipment] submit failed', submitRes.status, JSON.stringify(submitData));
      return jsonError(
        submitData?.message
            ? `EasyParcel: ${submitData.message}`
            : `Could not book EasyParcel shipment (${submitRes.status})`,
        502,
      );
    }
    const orderResult = submitData?.data?.[0];
    const shipmentResult = orderResult?.shipments?.[0];
    if (!shipmentResult || shipmentResult.status !== 'success') {
      console.error('[easyparcel-book-shipment] shipment not successful', JSON.stringify(submitData));
      // shipmentResult.errors is an array of arrays of {message, code, data}
      // — e.g. [[{"message":"Insufficient Credit Balance", ...}]] — not a
      // flat remark/reason field.
      const errorMessage = shipmentResult?.errors
        ?.flat()
        ?.map((e: { message?: string }) => e?.message)
        .filter(Boolean)
        .join('; ');
      return jsonError(
        `EasyParcel: ${errorMessage || 'shipment could not be booked'}`,
        502,
      );
    }
    const trackingNumber: string | undefined =
      shipmentResult?.awb_number ?? shipmentResult?.shipment_number;
    const shipmentId: string | undefined =
      shipmentResult?.shipment_number ?? orderResult?.order_details?.order_number;
    const awbUrl: string | undefined = shipmentResult?.awb_url;

    if (!trackingNumber) {
      console.error('[easyparcel-book-shipment] no tracking number in response', submitData);
      return jsonError('EasyParcel did not return a tracking number', 502);
    }

    // Mirrors track-register: a shipment being booked means the parcel is
    // (about to be) handed to the courier — advance paid/packing → shipped.
    const statusUpdate =
      order.status === 'paid' || order.status === 'packing' ? { status: 'shipped' } : {};

    await admin
      .from('orders')
      .update({
        qxpress_tracking_no: trackingNumber,
        tracking_provider: 'easyparcel',
        tracking_registered: true,
        tracking_status: 'Booked',
        tracking_updated_at: new Date().toISOString(),
        easyparcel_shipment_id: shipmentId ?? null,
        easyparcel_awb_url: awbUrl ?? null,
        ...statusUpdate,
      })
      .eq('id', order_id);

    if (statusUpdate.status) {
      await notifyOrder(order_id, { status: 'shipped' });
    }

    return new Response(
      JSON.stringify({ ok: true, tracking_number: trackingNumber, awb_url: awbUrl ?? null }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});
