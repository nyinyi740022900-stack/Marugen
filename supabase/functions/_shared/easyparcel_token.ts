// Shared by easyparcel-get-rates / easyparcel-book-shipment: resolves a
// live access_token for the connected EasyParcel account, refreshing it
// first if it's expired. The token itself is never returned to the
// Flutter app — only these two admin-only Edge Functions (plus
// easyparcel-oauth-callback, which writes the row) ever touch
// easyparcel_connection, matching that table's RLS (no client-facing
// policies at all).

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const clientId = Deno.env.get('EASYPARCEL_CLIENT_ID') ?? '';
const clientSecret = Deno.env.get('EASYPARCEL_CLIENT_SECRET') ?? '';

export class EasyParcelNotConnectedError extends Error {
  constructor() {
    super('EasyParcel is not connected. Connect it from Settings first.');
  }
}

/// Returns a valid access_token, transparently refreshing it (and
/// persisting the new tokens) if the current one has expired.
export async function getEasyParcelAccessToken(admin: SupabaseClient): Promise<string> {
  const { data: connection } = await admin
    .from('easyparcel_connection')
    .select('access_token, refresh_token, access_token_expires_at, refresh_token_expires_at')
    .eq('id', 1)
    .maybeSingle();

  if (!connection) throw new EasyParcelNotConnectedError();

  const now = Date.now();
  // 60s safety margin so a token that's about to expire mid-request still
  // gets refreshed rather than failing the actual API call.
  if (new Date(connection.access_token_expires_at).getTime() - 60_000 > now) {
    return connection.access_token as string;
  }

  if (new Date(connection.refresh_token_expires_at).getTime() <= now) {
    // Refresh token itself is dead — admin has to reconnect from Settings.
    throw new EasyParcelNotConnectedError();
  }

  const res = await fetch('https://api.easyparcel.com/oauth/token', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: connection.refresh_token as string,
    }),
  });
  if (!res.ok) {
    throw new Error(`EasyParcel token refresh failed (${res.status}): ${await res.text()}`);
  }
  const tokens = await res.json();

  await admin
    .from('easyparcel_connection')
    .update({
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token ?? connection.refresh_token,
      access_token_expires_at: new Date(now + tokens.expires_in * 1000).toISOString(),
      refresh_token_expires_at: tokens.refresh_token_expires_in
        ? new Date(now + tokens.refresh_token_expires_in * 1000).toISOString()
        : connection.refresh_token_expires_at,
    })
    .eq('id', 1);

  return tokens.access_token as string;
}
