// Supabase Edge Function: easyparcel-get-rates
//
// Admin-only. Given an order_id, calls EasyParcel's rate-quotation API
// using the shop's sender address (settings table) and the order's
// receiver address, and returns the list of courier options (with price)
// for the admin to pick from in the "Ship with EasyParcel" bottom sheet —
// see admin_delivery_screen.dart.
//
// Field names below follow https://easyparcel.github.io/OpenAPI/
// ("Shipment Quotations") as fetched during planning — re-verify against
// a real sandbox response if EasyParcel returns a 4xx here, since the
// live docs are the source of truth, not this comment.
//
// Deploy:  supabase functions deploy easyparcel-get-rates
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

    const { order_id } = await req.json();
    if (!order_id) return jsonError('order_id is required', 400);

    const { data: order } = await admin
      .from('orders')
      .select('id, shipping_address')
      .eq('id', order_id)
      .maybeSingle();
    if (!order) return jsonError('Order not found', 404);
    const shipping = order.shipping_address as Record<string, unknown> | null;
    if (!shipping) return jsonError('Order has no shipping address', 400);

    const { data: settings } = await admin
      .from('settings')
      .select(
        'shop_name, shop_phone, shop_postcode, shop_city, shop_state, shop_country, default_parcel_weight_kg',
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

    // Per the live docs (https://easyparcel.github.io/OpenAPI/ — "Shipment
    // Quotations"), weight/width/height/length/parcel_value are top-level
    // fields on each shipment item, siblings of sender/receiver — NOT
    // nested under a "parcel" object (that shape was guessed during
    // planning and got "The weight field is required" back from the API
    // even with a weight present, because the API never saw it there).
    // EasyParcel also encodes success/failure in the body's own
    // status_code — HTTP 200 can still wrap a per-item "status":"error".
    const quoteRes = await fetch('https://api.easyparcel.com/open_api/2026-06/shipment/quotations', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        shipment: [
          {
            sender: {
              postcode: settings.shop_postcode,
              subdivision_code: settings.shop_state ?? '',
              country: settings.shop_country ?? 'SG',
            },
            receiver: {
              postcode: shipping.postal_code,
              subdivision_code: '',
              country: 'SG',
            },
            weight: settings.default_parcel_weight_kg ?? 1,
          },
        ],
      }),
    });
    const quotes = await quoteRes.json();
    if (!quoteRes.ok || (quotes?.status_code && quotes.status_code !== 200)) {
      console.error('[easyparcel-get-rates] quotation failed', quoteRes.status, JSON.stringify(quotes));
      return jsonError(
        quotes?.message ? `EasyParcel: ${quotes.message}` : `Could not fetch EasyParcel rates (${quoteRes.status})`,
        502,
      );
    }

    const result = quotes?.data?.[0];
    if (!result || result.status === 'error') {
      const errors = result?.errors?.join(', ') ?? 'no couriers available';
      console.error('[easyparcel-get-rates] quotation item error', JSON.stringify(result));
      return jsonError(`EasyParcel: ${errors}`, 502);
    }

    const rates = ((result.quotations ?? []) as Array<Record<string, any>>).map((q) => ({
      service_id: q.courier?.service_id,
      courier_id: q.courier?.courier_id,
      courier_name: q.courier?.courier_name,
      price: q.pricing?.total_amount,
      currency: q.pricing?.currency,
    }));

    return new Response(JSON.stringify({ rates }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});
