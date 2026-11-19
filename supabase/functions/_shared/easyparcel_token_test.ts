import {
  type EasyParcelConnection,
  EasyParcelNotConnectedError,
  resolveEasyParcelAccessToken,
  type TokenPort,
} from "./easyparcel_token.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
const T0 = Date.parse("2026-11-19T00:00:00Z");
const iso = (ms: number) => new Date(ms).toISOString();
// An in-memory easyparcel_connection row with the same lease rule as
// claim_easyparcel_token_refresh (migration 0078), and a provider that
// rotates refresh tokens: a refresh token works exactly once.
function fixture(overrides: Partial<EasyParcelConnection> = {}) {
  let clock = T0;
  let row: (EasyParcelConnection & { refresh_started_at: number | null }) | null =
    {
      access_token: "access-old",
      refresh_token: "refresh-1",
      access_token_expires_at: iso(T0 - 1000),
      refresh_token_expires_at: iso(T0 + 86_400_000),
      refresh_started_at: null,
      ...overrides,
    };
  const state = {
    exchanges: [] as string[],
    storeFailures: 0,
    stores: 0,
    exchangeDelayMs: 0,
    setRow: (next: typeof row) => {
      row = next;
    },
    row: () => row,
    advance: (ms: number) => {
      clock += ms;
    },
  };
  let generation = 1;
  const port: TokenPort = {
    read: async () => row ? { ...row } : null,
    claim: async (refreshToken) => {
      if (
        !row || row.refresh_token !== refreshToken ||
        (row.refresh_started_at !== null &&
          row.refresh_started_at >= clock - 60_000)
      ) return false;
      row.refresh_started_at = clock;
      return true;
    },
    exchange: async (refreshToken) => {
      state.exchanges.push(refreshToken);
      if (state.exchangeDelayMs) {
        await new Promise((r) => setTimeout(r, state.exchangeDelayMs));
      }
      if (refreshToken !== `refresh-${generation}`) {
        throw new Error("provider: refresh token already used");
      }
      generation++;
      return {
        access_token: `access-${generation}`,
        refresh_token: `refresh-${generation}`,
        expires_in: 3600,
        refresh_token_expires_in: 86_400,
      };
    },
    store: async (previous, connection) => {
      state.stores++;
      if (state.storeFailures > 0) {
        state.storeFailures--;
        throw new Error("database unavailable");
      }
      if (!row || row.refresh_token !== previous) return false;
      row = { ...connection, refresh_started_at: null };
      return true;
    },
    now: () => clock,
    sleep: async (ms) => {
      clock += ms;
      await new Promise((r) => setTimeout(r, 1));
    },
  };
  return { port, state };
}
Deno.test("a live access token is returned without contacting EasyParcel", async () => {
  const f = fixture({ access_token_expires_at: iso(T0 + 600_000) });
  assert(
    await resolveEasyParcelAccessToken(f.port) === "access-old",
    "wrong token",
  );
  assert(f.state.exchanges.length === 0, "refreshed a live token");
});
Deno.test("an expired token is refreshed once, stored, and the lease released", async () => {
  const f = fixture();
  assert(await resolveEasyParcelAccessToken(f.port) === "access-2", "token");
  const row = f.state.row()!;
  assert(
    row.access_token === "access-2" && row.refresh_token === "refresh-2" &&
      row.refresh_started_at === null,
    "new tokens not stored or lease kept",
  );
});
Deno.test("concurrent requests spend the refresh token once and all get the new token", async () => {
  const f = fixture();
  f.state.exchangeDelayMs = 20;
  const tokens = await Promise.all(
    Array.from({ length: 5 }, () => resolveEasyParcelAccessToken(f.port)),
  );
  assert(
    f.state.exchanges.length === 1,
    `refresh token sent ${f.state.exchanges.length} times`,
  );
  assert(tokens.every((t) => t === "access-2"), `tokens: ${tokens}`);
  assert(f.state.row()!.refresh_token === "refresh-2", "stale token stored");
});
Deno.test("a failed save is retried, and reported if it never lands", async () => {
  const retried = fixture();
  retried.state.storeFailures = 1;
  assert(
    await resolveEasyParcelAccessToken(retried.port) === "access-2",
    "token",
  );
  assert(
    retried.state.stores === 2 &&
      retried.state.row()!.refresh_token === "refresh-2",
    "save was not retried",
  );
  const lost = fixture();
  lost.state.storeFailures = 5;
  // The caller still gets the valid access token for this request.
  assert(await resolveEasyParcelAccessToken(lost.port) === "access-2", "token");
  assert(lost.state.stores === 2, "expected exactly two attempts");
});
Deno.test("a reconnect during the refresh is not overwritten", async () => {
  const f = fixture();
  const exchange = f.port.exchange;
  f.port.exchange = async (token) => {
    const tokens = await exchange(token);
    // The admin reconnects EasyParcel while the refresh is in flight.
    f.state.setRow({
      access_token: "access-reconnected",
      refresh_token: "refresh-reconnected",
      access_token_expires_at: iso(T0 + 3_600_000),
      refresh_token_expires_at: iso(T0 + 86_400_000),
      refresh_started_at: null,
    });
    return tokens;
  };
  await resolveEasyParcelAccessToken(f.port);
  assert(
    f.state.row()!.refresh_token === "refresh-reconnected",
    "the new connection was overwritten",
  );
});
Deno.test("waiting for a refresh that never finishes ends with safe copy, not a second refresh", async () => {
  const f = fixture();
  // Someone else holds the lease and never stores a result.
  f.state.row()!.refresh_started_at = T0;
  f.port.sleep = async () => {}; // the lease never ages in this test
  let message = "";
  try {
    await resolveEasyParcelAccessToken(f.port);
  } catch (error) {
    message = (error as Error).message;
  }
  assert(/being refreshed/.test(message), `unexpected: ${message}`);
  assert(f.state.exchanges.length === 0, "refresh token was spent anyway");
});
Deno.test("an abandoned lease expires so refreshing can resume", async () => {
  const f = fixture();
  f.state.row()!.refresh_started_at = T0 - 61_000;
  assert(await resolveEasyParcelAccessToken(f.port) === "access-2", "token");
});
Deno.test("no connection or a dead refresh token asks the admin to reconnect", async () => {
  const none = fixture();
  none.state.setRow(null);
  const dead = fixture({ refresh_token_expires_at: iso(T0 - 1) });
  for (const f of [none, dead]) {
    let error: unknown;
    try {
      await resolveEasyParcelAccessToken(f.port);
    } catch (e) {
      error = e;
    }
    assert(error instanceof EasyParcelNotConnectedError, "wrong error");
    assert(f.state.exchanges.length === 0, "contacted the provider");
  }
});
