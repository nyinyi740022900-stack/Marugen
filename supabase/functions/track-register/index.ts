// Supabase Edge Function: track-register
//
// Registers an order's courier tracking number with 17TRACK (any carrier —
// Qxpress or otherwise; 17TRACK auto-detects the carrier from the number
// format if you don't pass one). Once registered, 17TRACK starts polling
// the carrier and will push status updates to `track-webhook`.
//
// Only admins (staff/owner) may call this — enforced via the caller's JWT
// + a `profiles.role` check, same pattern as the app's `is_admin()` RLS.
//
// Deploy:  supabase functions deploy track-register
// Secrets: supabase secrets set TRACK17_API_KEY=xxx
//          (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are already set for every project)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const track17ApiKey = Deno.env.get('TRACK17_API_KEY') ?? '';
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

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

    // Verify the caller is a signed-in admin (staff/owner), not just any user.
    const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
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

    const { order_id, tracking_number, carrier_code } = await req.json();
    if (!order_id || !tracking_number) {
      return jsonError('order_id and tracking_number are required', 400);
    }

    // 17TRACK v2.4 register — https://api.17track.net/track/v2.4/register
    const payload: Record<string, unknown> = { number: tracking_number };
    if (carrier_code) payload.carrier = carrier_code;

    const trackRes = await fetch('https://api.17track.net/track/v2.4/register', {
      method: 'POST',
      headers: {
        '17token': track17ApiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify([payload]),
    });

    const trackData = await trackRes.json();
    const accepted = trackData?.data?.accepted?.[0];
    const rejected = trackData?.data?.rejected?.[0];

    if (!trackRes.ok || rejected) {
      const reason = rejected?.error?.message ?? `17TRACK register failed (${trackRes.status})`;
      // A "number already registered" rejection is fine — it's already being
      // tracked from an earlier attempt. Anything else is a real failure.
      if (!String(reason).toLowerCase().includes('already')) {
        return jsonError(reason, 502);
      }
    }

    await admin
      .from('orders')
      .update({
        qxpress_tracking_no: tracking_number,
        tracking_carrier_code: accepted?.carrier ?? carrier_code ?? null,
        tracking_registered: true,
        tracking_status: 'Registered',
        tracking_updated_at: new Date().toISOString(),
      })
      .eq('id', order_id);

    return new Response(JSON.stringify({ ok: true, carrier: accepted?.carrier ?? carrier_code ?? null }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
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
