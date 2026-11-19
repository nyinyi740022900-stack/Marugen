// Outbound call limits and response-safety helpers shared by every function.
//
// An Edge Function that waits on a provider with no limit holds its worker
// (and the caller's spinner) until the platform kills it, and the caller then
// cannot tell "failed" from "still running". Every outbound fetch goes through
// fetchWithTimeout with one of these budgets.
export const TIMEOUT_MS = {
  // Paid EasyParcel booking. Generous: giving up early does NOT undo a booking
  // the provider may already have accepted (see easyparcel-book-shipment).
  booking: 30_000,
  // Read-only provider calls: tracking, shipment details, 17TRACK.
  provider: 15_000,
  // OAuth token exchange and refresh.
  token: 15_000,
  // One FCM message.
  push: 10_000,
  // Our own send-order-notification function; best effort, never blocks a
  // payment or tracking write for long.
  notify: 10_000,
} as const;

/** fetch() that aborts, body read included, after `ms` milliseconds. */
export function fetchWithTimeout(
  input: string | URL | Request,
  init: RequestInit,
  ms: number,
): Promise<Response> {
  return fetch(input, { ...init, signal: AbortSignal.timeout(ms) });
}

/** True for the error fetchWithTimeout raises when its budget runs out. */
export function isTimeoutError(error: unknown): boolean {
  const name = (error as { name?: unknown } | null)?.name;
  return name === "TimeoutError" || name === "AbortError";
}

/** Text from a request made safe to place inside HTML. */
export function escapeHtml(value: string): string {
  return value.replace(
    /[&<>"'`]/g,
    (c) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
        "`": "&#96;",
      })[c]!,
  );
}
