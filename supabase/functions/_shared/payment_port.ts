import type { PaymentPort } from "./payment_lifecycle.ts";
import { fetchWithTimeout, TIMEOUT_MS } from "./http.ts";
// Adapters remain at the edge; lifecycle tests use isolated ports.
export function createPaymentPort(
  admin: any,
  stripe: any,
  url: string,
  key: string,
): PaymentPort {
  return {
    getOrder: async (orderId, intentId) => {
      let q = admin.from("orders").select(
        "id,user_id,status,total,stripe_payment_intent_id",
      );
      q = orderId
        ? q.eq("id", orderId)
        : q.eq("stripe_payment_intent_id", intentId);
      const { data, error } = await q.maybeSingle();
      if (error) throw error;
      return data;
    },
    getIntent: async (id) => stripe.paymentIntents.retrieve(id),
    cancelIntent: async (id) =>
      stripe.paymentIntents.cancel(id, {}, { idempotencyKey: `cancel_${id}` }),
    transition: async (id, intentId, status) => {
      let q = admin.from("orders").update({ status }).eq("id", id).eq(
        "status",
        "pending",
      );
      q = intentId
        ? q.eq("stripe_payment_intent_id", intentId)
        : q.is("stripe_payment_intent_id", null);
      const { data, error } = await q.select("id").maybeSingle();
      if (error) throw error;
      return !!data;
    },
    notify: async (orderId, status) => {
      try {
        // Best effort: a slow notification must not hold the Stripe webhook
        // open after the order is already recorded as paid.
        const r = await fetchWithTimeout(
          `${url}/functions/v1/send-order-notification`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${key}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ order_id: orderId, status }),
          },
          TIMEOUT_MS.notify,
        );
        if (!r.ok) {
          console.error("Payment notification failed", orderId, r.status);
        }
      } catch (e) {
        console.error("Payment notification failed", orderId, e);
      }
    },
  };
}
