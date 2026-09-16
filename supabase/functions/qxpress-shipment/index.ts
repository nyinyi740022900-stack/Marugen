// Supabase Edge Function: qxpress-shipment
//
// Creates a shipment with Qxpress (Singapore) for a paid order and writes
// the resulting tracking number back onto the order row.
//
// ⚠️ TODO before going live: confirm with Qxpress (a) the exact REST
// endpoint/auth scheme for your merchant account, and (b) whether live fish
// are an accepted parcel type — until confirmed, keep live-fish orders on
// "Store Pickup" in the admin Delivery screen instead of calling this.
//
// Deploy:  supabase functions deploy qxpress-shipment
// Secrets: supabase secrets set QXPRESS_API_KEY=xxx QXPRESS_API_BASE_URL=https://api.qxpress.net
//          supabase secrets set SUPABASE_SERVICE_ROLE_KEY=xxx (usually already set)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const qxpressApiKey = Deno.env.get('QXPRESS_API_KEY') ?? '';
const qxpressBaseUrl = Deno.env.get('QXPRESS_API_BASE_URL') ?? 'https://api.qxpress.net';

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { order_id, address } = await req.json();
    if (!order_id) {
      return new Response(JSON.stringify({ error: 'order_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // --- Replace this block with the real Qxpress API call once you have
    // --- their merchant API docs. Shape below is a placeholder guess.
    const qxRes = await fetch(`${qxpressBaseUrl}/v1/shipments`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${qxpressApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        reference_no: order_id,
        recipient: address ?? {},
      }),
    });

    if (!qxRes.ok) {
      const text = await qxRes.text();
      throw new Error(`Qxpress API error (${qxRes.status}): ${text}`);
    }

    const qxData = await qxRes.json();
    const trackingNo = qxData.tracking_number ?? qxData.trackingNo ?? null;

    await supabaseAdmin
      .from('orders')
      .update({ status: 'shipped', qxpress_tracking_no: trackingNo, shipping_address: address })
      .eq('id', order_id);

    return new Response(JSON.stringify({ tracking_number: trackingNo }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: `${err}` }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
