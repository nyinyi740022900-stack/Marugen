// Supabase Edge Function: track-webhook
//
// Receives push notifications from 17TRACK whenever a registered tracking
// number's status changes, and writes the latest status onto the matching
// order. This is the "Package Webhook" URL you paste into 17TRACK's
// dashboard (Settings → Package Webhook → URL).
//
// Deploy:  supabase functions deploy track-webhook --no-verify-jwt
// (--no-verify-jwt because 17TRACK calls this directly, not through your app's auth)
//
// 17TRACK's push payload shape (v2.x):
// { "event": "TRACKING_UPDATED", "data": { "number": "...", "carrier": 100001,
//   "track_info": { "latest_status": { "status": "...", "sub_status": "..." },
//                    "latest_event": { "description": "...", "time_iso": "..." } } } }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

Deno.serve(async (req) => {
  try {
    const body = await req.json();
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

    await supabaseAdmin
      .from('orders')
      .update({
        tracking_status: status ?? null,
        tracking_status_detail: eventDescription ?? null,
        tracking_updated_at: new Date().toISOString(),
      })
      .eq('qxpress_tracking_no', number);

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
