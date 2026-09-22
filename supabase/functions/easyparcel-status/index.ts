// Supabase Edge Function: easyparcel-status
//
// Admin-only. Returns {connected, connected_at} — the Flutter Settings
// screen polls this after the admin returns from the OAuth browser flow.
// Never returns the actual tokens (easyparcel_connection has no
// client-facing RLS policy at all; only service-role callers like this
// function can read it).
//
// Deploy:  supabase functions deploy easyparcel-status
// Secrets: none new.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

    const { data: connection } = await admin
      .from('easyparcel_connection')
      .select('connected_at, refresh_token_expires_at')
      .eq('id', 1)
      .maybeSingle();

    const connected =
      !!connection && new Date(connection.refresh_token_expires_at).getTime() > Date.now();

    return new Response(
      JSON.stringify({ connected, connected_at: connected ? connection!.connected_at : null }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});
