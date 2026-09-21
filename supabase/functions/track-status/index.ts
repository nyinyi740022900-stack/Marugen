// Supabase Edge Function: track-status
//
// On-demand pull of a tracking number's current status from 17TRACK —
// used for a manual "Refresh" action instead of waiting for the next
// webhook push (pushes can take a while after first registering a number).
//
// Deploy:  supabase functions deploy track-status
// Secrets: supabase secrets set TRACK17_API_KEY=xxx

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const track17ApiKey = Deno.env.get('TRACK17_API_KEY') ?? '';
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
// Prefer the new publishable/secret key pair (set explicitly via
// `supabase secrets set`) over the legacy JWT anon/service_role names the
// platform auto-injects, so this keeps working whether or not legacy
// JWT-based API keys are later disabled project-wide.
const anonKey = Deno.env.get('SB_ANON_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceRoleKey =
  Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonError('Missing Authorization header', 401);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return jsonError('Unauthorized', 401);

    const { order_id } = await req.json();
    if (!order_id) return jsonError('order_id is required', 400);

    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Only the order's own customer or an admin may pull its status.
    const { data: order } = await admin
      .from('orders')
      .select('id, user_id, qxpress_tracking_no, tracking_carrier_code')
      .eq('id', order_id)
      .maybeSingle();
    if (!order) return jsonError('Order not found', 404);

    if (order.user_id !== user.id) {
      const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle();
      if (!profile || (profile.role !== 'staff' && profile.role !== 'owner')) {
        return jsonError('Not authorized to view this order', 403);
      }
    }

    if (!order.qxpress_tracking_no) return jsonError('This order has no tracking number yet', 400);

    const payload: Record<string, unknown> = { number: order.qxpress_tracking_no };
    if (order.tracking_carrier_code) payload.carrier = order.tracking_carrier_code;

    const trackRes = await fetch('https://api.17track.net/track/v2.4/gettrackinfo', {
      method: 'POST',
      headers: {
        '17token': track17ApiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify([payload]),
    });

    const trackData = await trackRes.json();
    const info = trackData?.data?.accepted?.[0]?.track_info;
    const status: string | undefined = info?.latest_status?.status;
    const eventDescription: string | undefined = info?.latest_event?.description;

    if (status) {
      await admin
        .from('orders')
        .update({
          tracking_status: status,
          tracking_status_detail: eventDescription ?? null,
          tracking_updated_at: new Date().toISOString(),
        })
        .eq('id', order_id);
    }

    return new Response(
      JSON.stringify({ status: status ?? null, detail: eventDescription ?? null }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});

function jsonError(message: string, status: number) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
