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
      const e = error as { code?: string; message?: string };
      const status = e.code === "42501"
        ? 403
        : e.code === "P0002"
        ? 404
        : e.code === "P0001"
        ? 409
        : 500;
      return json({
        error: e.message || "Cancellation request could not be processed",
      }, status);
    }
  };
}
