// Shared by easyparcel-get-rates / easyparcel-book-shipment: resolves a
// live access_token for the connected EasyParcel account, refreshing it
// first if it's expired. The token itself is never returned to the
// Flutter app — only these two admin-only Edge Functions (plus
// easyparcel-oauth-callback, which writes the row) ever touch
// easyparcel_connection, matching that table's RLS (no client-facing
// policies at all).
//
// Only one refresh runs at a time. Two requests that both found the token
// expired used to send the same refresh token to EasyParcel; if the provider
// rotates refresh tokens, the slower request then stored a dead one and the
// shop had to reconnect. The refresher now takes a short database lease
// (claim_easyparcel_token_refresh, migration 0078) and everyone else waits
// for the token it stores. If the refresh fails, the refresher hands the
// lease straight back (release_easyparcel_token_refresh, migration 0079)
// instead of leaving everyone else waiting for it to expire.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { fetchWithTimeout, TIMEOUT_MS } from './http.ts';

const clientId = Deno.env.get('EASYPARCEL_CLIENT_ID') ?? '';
const clientSecret = Deno.env.get('EASYPARCEL_CLIENT_SECRET') ?? '';

export class EasyParcelNotConnectedError extends Error {
  constructor() {
    super('EasyParcel is not connected. Connect it from Settings first.');
  }
}

/**
 * A refresh that did not produce a token. The message is written for staff
 * and is safe to show; provider and database detail goes to the logs only.
 */
export class EasyParcelRefreshError extends Error {}
const REFRESH_FAILED_MESSAGE =
  'EasyParcel connection could not be refreshed. Try again, or reconnect it from Settings.';

export type EasyParcelConnection = {
  access_token: string;
  refresh_token: string;
  access_token_expires_at: string;
  refresh_token_expires_at: string;
};
export type RefreshedTokens = {
  access_token: string;
  refresh_token?: string | null;
  expires_in: number;
  refresh_token_expires_in?: number | null;
};
export interface TokenPort {
  read(): Promise<EasyParcelConnection | null>;
  /** Atomically take the refresh lease for this exact refresh token. */
  claim(refreshToken: string): Promise<boolean>;
  exchange(refreshToken: string): Promise<RefreshedTokens>;
  /** Hand back a lease taken with this exact refresh token after a failed refresh. */
  release(refreshToken: string): Promise<void>;
  /** Store the new tokens and release the lease; false if nothing was written. */
  store(
    previousRefreshToken: string,
    connection: EasyParcelConnection,
  ): Promise<boolean>;
  now(): number;
  sleep(ms: number): Promise<void>;
}

// 60s safety margin so a token that's about to expire mid-request still
// gets refreshed rather than failing the actual API call.
const EXPIRY_MARGIN_MS = 60_000;
// How long a request waits for another request's refresh: a little longer
// than that refresh can take (TIMEOUT_MS.token).
const WAIT_STEP_MS = 500;
const WAIT_STEPS = Math.ceil((TIMEOUT_MS.token + 3_000) / WAIT_STEP_MS);
// The database lease lasts 60 s. It is handed back only while it is
// certainly still this request's own: after that it has expired (or is about
// to) and may already belong to another request with the same refresh token.
const RELEASE_WINDOW_MS = 45_000;

function usable(connection: EasyParcelConnection, now: number): boolean {
  return new Date(connection.access_token_expires_at).getTime() -
      EXPIRY_MARGIN_MS > now;
}

export async function resolveEasyParcelAccessToken(
  port: TokenPort,
): Promise<string> {
  let connection = await port.read();
  if (!connection) throw new EasyParcelNotConnectedError();
  if (usable(connection, port.now())) return connection.access_token;

  let claimStartedAt = 0;
  for (let step = 0;; step++) {
    if (
      new Date(connection.refresh_token_expires_at).getTime() <= port.now()
    ) {
      // Refresh token itself is dead — admin has to reconnect from Settings.
      throw new EasyParcelNotConnectedError();
    }
    // Taken before the claim, so the lease can only be younger than this.
    claimStartedAt = port.now();
    if (await port.claim(connection.refresh_token)) break;
    // Another request holds the lease (or the tokens just changed). Wait for
    // its result instead of spending the same refresh token a second time.
    if (step >= WAIT_STEPS) {
      throw new EasyParcelRefreshError(
        'EasyParcel connection is being refreshed. Try again in a moment.',
      );
    }
    await port.sleep(WAIT_STEP_MS);
    connection = await port.read();
    if (!connection) throw new EasyParcelNotConnectedError();
    if (usable(connection, port.now())) return connection.access_token;
  }

  let tokens: RefreshedTokens;
  try {
    tokens = await port.exchange(connection.refresh_token);
  } catch (error) {
    // Rejected, timed out or unreadable: nobody is refreshing any more, so
    // do not leave the other requests waiting out the rest of the lease.
    if (port.now() - claimStartedAt < RELEASE_WINDOW_MS) {
      try {
        await port.release(connection.refresh_token);
      } catch (releaseError) {
        // Not fatal: the lease expires by itself.
        console.error(
          '[easyparcel-token] refresh lease was not released',
          releaseError,
        );
      }
    }
    if (error instanceof EasyParcelRefreshError) throw error;
    console.error('[easyparcel-token] refresh did not complete', error);
    throw new EasyParcelRefreshError(REFRESH_FAILED_MESSAGE);
  }
  const now = port.now();
  const next: EasyParcelConnection = {
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token ?? connection.refresh_token,
    access_token_expires_at: new Date(now + tokens.expires_in * 1000)
      .toISOString(),
    refresh_token_expires_at: tokens.refresh_token_expires_in
      ? new Date(now + tokens.refresh_token_expires_in * 1000).toISOString()
      : connection.refresh_token_expires_at,
  };
  // The provider may already have retired the old refresh token, so losing
  // this write can disconnect the shop: try twice and say so loudly. The
  // access token in hand is still valid, so this request carries on.
  let stored = false;
  for (let attempt = 0; attempt < 2 && !stored; attempt++) {
    try {
      stored = await port.store(connection.refresh_token, next);
      // Nothing written means the connection was replaced meanwhile (the
      // admin reconnected); the stored tokens are newer than ours. Done.
      if (!stored) return tokens.access_token;
    } catch (error) {
      console.error(
        '[easyparcel-token] refreshed tokens were not saved',
        attempt + 1,
        error,
      );
    }
  }
  if (!stored) {
    console.error(
      '[easyparcel-token] refresh succeeded but the new tokens are not stored; ' +
        'if EasyParcel calls start failing, reconnect it from Settings',
    );
  }
  return tokens.access_token;
}

function tokenPort(admin: SupabaseClient): TokenPort {
  return {
    read: async () => {
      const { data, error } = await admin
        .from('easyparcel_connection')
        .select(
          'access_token, refresh_token, access_token_expires_at, refresh_token_expires_at',
        )
        .eq('id', 1)
        .maybeSingle();
      if (error) throw error;
      return data as EasyParcelConnection | null;
    },
    claim: async (refreshToken) => {
      const { data, error } = await admin.rpc('claim_easyparcel_token_refresh', {
        p_refresh_token: refreshToken,
      });
      if (error) throw error;
      return data === true;
    },
    exchange: async (refreshToken) => {
      const res = await fetchWithTimeout(
        'https://api.easyparcel.com/oauth/token',
        {
          method: 'POST',
          headers: {
            Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: new URLSearchParams({
            grant_type: 'refresh_token',
            refresh_token: refreshToken,
          }),
        },
        TIMEOUT_MS.token,
      );
      if (!res.ok) {
        // The provider's body stays in the logs; callers pass this message on.
        console.error(
          '[easyparcel-token] refresh rejected',
          res.status,
          await res.text(),
        );
        throw new EasyParcelRefreshError(REFRESH_FAILED_MESSAGE);
      }
      const tokens = await res.json();
      if (
        typeof tokens?.access_token !== 'string' || !tokens.access_token ||
        !Number.isFinite(tokens.expires_in)
      ) {
        throw new EasyParcelRefreshError(REFRESH_FAILED_MESSAGE);
      }
      return tokens as RefreshedTokens;
    },
    release: async (refreshToken) => {
      const { error } = await admin.rpc('release_easyparcel_token_refresh', {
        p_refresh_token: refreshToken,
      });
      if (error) throw error;
    },
    store: async (previousRefreshToken, connection) => {
      const { data, error } = await admin
        .from('easyparcel_connection')
        .update({ ...connection, refresh_started_at: null })
        .eq('id', 1)
        // Never overwrite a connection the admin replaced during the refresh.
        .eq('refresh_token', previousRefreshToken)
        .select('id')
        .maybeSingle();
      if (error) throw error;
      return !!data;
    },
    now: () => Date.now(),
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  };
}

/// Returns a valid access_token, transparently refreshing it (and
/// persisting the new tokens) if the current one has expired.
export function getEasyParcelAccessToken(admin: SupabaseClient): Promise<string> {
  return resolveEasyParcelAccessToken(tokenPort(admin));
}
