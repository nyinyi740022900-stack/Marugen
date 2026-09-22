// Supabase Edge Function: easyparcel-oauth-callback
//
// The OAuth 2.0 redirect target EasyParcel sends the admin's browser back
// to after they approve the connection (see admin_settings_screen.dart's
// "Connect EasyParcel" button, which opens
// https://api.easyparcel.com/oauth/login?client_id=...&redirect_uri=<this
// function's URL>&state=...). Exchanges the one-time `code` for an
// access/refresh token pair and stores it in the singleton
// `easyparcel_connection` row — the only place those tokens live; the
// Flutter app never sees them, only a connected/not-connected boolean via
// easyparcel-status.
//
// Must be registered as an Allowed Redirect URI for the "Marugen Koi Farm
// App" in the EasyParcel Developer Hub (Configuration → Application URIs)
// — add this function's URL alongside whatever's already there.
//
// Deploy:  supabase functions deploy easyparcel-oauth-callback --no-verify-jwt
// (--no-verify-jwt because EasyParcel's browser redirect carries no
// Supabase JWT — this endpoint is public by nature, same as any OAuth
// callback; the one-time `code` combined with our client_secret is what's
// actually being verified.)
// Secrets: supabase secrets set EASYPARCEL_CLIENT_ID=xxx EASYPARCEL_CLIENT_SECRET=xxx

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey =
  Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const clientId = Deno.env.get('EASYPARCEL_CLIENT_ID') ?? '';
const clientSecret = Deno.env.get('EASYPARCEL_CLIENT_SECRET') ?? '';

// This function's own URL — EasyParcel's token exchange requires the same
// redirect_uri that was used in the authorize step.
const redirectUri = `${supabaseUrl}/functions/v1/easyparcel-oauth-callback`;

const admin = createClient(supabaseUrl, serviceRoleKey);

function htmlResponse(body: string, status = 200) {
  return new Response(
    `<!doctype html><html><body style="font-family:sans-serif;text-align:center;padding:48px">${body}</body></html>`,
    { status, headers: { 'Content-Type': 'text/html' } },
  );
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const code = url.searchParams.get('code');
    const error = url.searchParams.get('error');
    if (error) {
      return htmlResponse(`<h2>EasyParcel connection failed</h2><p>${error}</p>`, 400);
    }
    if (!code) {
      return htmlResponse('<h2>Missing authorization code</h2>', 400);
    }

    const tokenRes = await fetch('https://api.easyparcel.com/oauth/token', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: redirectUri,
      }),
    });
    if (!tokenRes.ok) {
      const detail = await tokenRes.text();
      console.error('[easyparcel-oauth-callback] token exchange failed', tokenRes.status, detail);
      return htmlResponse('<h2>Could not connect EasyParcel</h2><p>Please try again from Settings.</p>', 502);
    }
    const tokens = await tokenRes.json();
    const now = Date.now();

    const { error: dbError } = await admin.from('easyparcel_connection').upsert({
      id: 1,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      access_token_expires_at: new Date(now + tokens.expires_in * 1000).toISOString(),
      refresh_token_expires_at: new Date(now + tokens.refresh_token_expires_in * 1000).toISOString(),
      connected_at: new Date().toISOString(),
    });
    if (dbError) {
      console.error('[easyparcel-oauth-callback] failed to store tokens', dbError);
      return htmlResponse('<h2>Could not save the connection</h2>', 500);
    }

    return htmlResponse('<h2>✅ EasyParcel connected</h2><p>You can close this tab and return to the app.</p>');
  } catch (err) {
    console.error('[easyparcel-oauth-callback] error', err);
    return htmlResponse('<h2>Something went wrong</h2>', 500);
  }
});
