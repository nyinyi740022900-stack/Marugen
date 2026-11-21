import type { CancellationAction } from "./cancellation_lifecycle.ts";
export type CancellationApi = {
  authenticate: (authorization: string) => Promise<string | null>;
  execute: (
    orderId: string,
    actorId: string,
    action: CancellationAction,
    reason?: string,
  ) => Promise<unknown>;
};
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
// The only database messages a caller may see: the business rules raised by
// transition_order_cancellation (0066). Every other message, including a raw
// Postgres or trigger error carrying the same code, becomes fixed copy.
const CANCELLATION_RULES = new Set([
  "Invalid cancellation action",
  "Cancellation was declined; please contact support",
  "Only paid, unshipped Stripe orders can request cancellation",
  "Delivery booking has already started; please contact support",
  "A cancellation reason of 1 to 500 characters is required",
  "No cancellation request exists",
  "Only an approved cancellation has a refund to refresh",
  "Cancellation request already decided",
  "Review note must be at most 500 characters",
  "A reason is required when declining cancellation",
]);
export function cancellationFailure(
  error: unknown,
): { status: number; message: string } {
  const e = (error ?? {}) as { code?: string; message?: string };
  if (e.code === "42501") {
    return { status: 403, message: "Cancellation access denied" };
  }
  if (e.code === "P0002") return { status: 404, message: "Order not found" };
  if (e.code === "P0001") {
    return {
      status: 409,
      message:
        typeof e.message === "string" && CANCELLATION_RULES.has(e.message)
          ? e.message
          : "This cancellation could not be completed. Refresh the order and try again.",
    };
  }
  return {
    status: 500,
    message: "Cancellation request could not be processed",
  };
}
export function createCancellationHandler(
  api: CancellationApi,
): (req: Request) => Promise<Response> {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  return async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") return json({ error: "POST required" }, 405);
    try {
      const token = req.headers.get("Authorization");
      const actor = token ? await api.authenticate(token) : null;
      if (!actor) return json({ error: "Unauthorized" }, 401);
      let body;
      try {
        body = await req.json();
      } catch {
        return json({ error: "Invalid JSON body" }, 400);
      }
      if (
        !body || typeof body !== "object" ||
        typeof body.order_id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          body.order_id,
        )
      ) return json({ error: "A valid order_id is required" }, 400);
      if (!["request", "approve", "reject", "refresh"].includes(body.action)) {
        return json({ error: "Invalid cancellation action" }, 400);
      }
      if (
        body.reason != null &&
        (typeof body.reason !== "string" || body.reason.length > 500)
      ) return json({ error: "Reason must be at most 500 characters" }, 400);
      const reason = body.reason?.trim() ||
        (body.action === "request"
          ? "Customer requested cancellation"
          : undefined);
      return json(await api.execute(body.order_id, actor, body.action, reason));
    } catch (error) {
      const { status, message } = cancellationFailure(error);
      console.error("Cancellation request failed", status, error);
      return json({ error: message }, status);
    }
  };
}
