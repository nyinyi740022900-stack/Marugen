// Supabase Edge Function: easyparcel-oauth-start
//
// Admin-only. Generates and stores a single-use OAuth `state` value that
// easyparcel-oauth-callback later validates — closes the CSRF gap where
// the callback used to accept any `code` for any EasyParcel account with
// nothing binding the request back to the admin session that started it
// (see 0047_easyparcel_oauth_state.sql). admin_settings_screen.dart calls
// this before building the https://api.easyparcel.com/oauth/login URL,
// instead of generating `state` locally and never persisting it.
//
// Deploy:  supabase functions deploy easyparcel-oauth-start
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

    // Opportunistic cleanup of abandoned states (started but never
    // completed) — keeps the table from growing unbounded. Not load
    // bearing for correctness; the callback's own age check is what
    // actually rejects a stale state.
    await admin
      .from('easyparcel_oauth_state')
      .delete()
      .lt('created_at', new Date(Date.now() - 60 * 60 * 1000).toISOString());

    const state = crypto.randomUUID();
    const { error: insertError } = await admin
      .from('easyparcel_oauth_state')
      .insert({ state });
    if (insertError) {
      console.error('[easyparcel-oauth-start] failed to store state', insertError);
      return jsonError('Could not start EasyParcel connection', 500);
    }

    return new Response(JSON.stringify({ state }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});
