import Stripe from "https://esm.sh/stripe@17?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createCancellationHandler } from "../_shared/cancellation_api.ts";
import {
  type CancellationRequest,
  handleCancellation,
} from "../_shared/cancellation_lifecycle.ts";
import { createRefundPort } from "../_shared/refund_port.ts";
import { pushToRecipients } from "../_shared/push.ts";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const anon = Deno.env.get("SB_ANON_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ??
  "";
const key = Deno.env.get("SB_SERVICE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(url, key);
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-06-20",
});

async function notify(request: CancellationRequest) {
  // Inbox rows use dedicated keys; cancellation is not a fake order status.
  const requested = request.status === "requested";
  const { data: staff, error } = requested
    ? await admin.from("profiles").select("id").in("role", ["owner", "staff"])
    : { data: [], error: null };
  if (error) throw error;
  const recipients = requested
    ? (staff ?? []).map((p: { id: string }) => p.id)
    : request.user_id ? [request.user_id] : [];
  if (!recipients.length) return;
  const title = requested
    ? "Cancellation requested"
    : request.status === "approved"
    ? "Cancellation approved"
    : "Cancellation declined";
  const body = requested
    ? "A customer requested cancellation. Review the order before fulfillment."
    : request.status === "approved"
    ? "Your cancellation was approved. The shop will arrange your refund; check the order for the latest refund status."
    : `Your cancellation request was declined. ${
      request.review_note ?? "Please contact the shop for help."
    }`;
  const key = `cancellation_${request.status}`;
  const { data: inserted, error: writeError } = await admin
    .from("notifications")
    .upsert(
      recipients.map((id: string) => ({
        user_id: id,
        order_id: request.order_id,
        type: requested ? "admin_alert" : "order_status",
        key,
        title,
        body,
      })),
      { onConflict: "order_id,user_id,key", ignoreDuplicates: true },
    )
    .select("user_id");
  if (writeError) throw writeError;
  // Only rows inserted by this call get a push, so a retry stays silent.
  const push = await pushToRecipients(
    admin,
    (inserted ?? []).map((r: { user_id: string }) => ({
      userId: r.user_id,
      title,
      body,
    })),
    { order_id: request.order_id, event: key },
  );
  if (push.error) console.error("Cancellation push failed", push.error);
}
Deno.serve(createCancellationHandler({
  authenticate: async (authorization) => {
    const client = createClient(url, anon, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user }, error } = await client.auth.getUser();
    return error ? null : user?.id ?? null;
  },
  execute: async (orderId, actorId, action, reason) => {
    const result = await handleCancellation(orderId, actorId, action, reason, {
      port: createRefundPort(admin, stripe, url, key),
      transition: async (id, actor, operation, note) => {
        const { data, error } = await admin.rpc(
          "transition_order_cancellation",
          {
            p_order_id: id,
            p_actor_id: actor,
            p_action: operation,
            p_reason: note ?? null,
          },
        );
        if (error) throw error;
        if (!data?.request) {
          throw new Error("Cancellation state was not confirmed");
        }
        return data;
      },
    });
    if (result.changed) {
      try {
        await notify(result.request);
      } catch (error) {
        console.error("Cancellation inbox notification failed", orderId, error);
      }
    }
    return result;
  },
}));
