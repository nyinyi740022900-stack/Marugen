import { createPaymentPort } from "./payment_port.ts";
import type { RefundPort } from "./refund_lifecycle.ts";

export function createRefundPort(
  admin: any,
  stripe: any,
  url: string,
  key: string,
): RefundPort {
  const payments = createPaymentPort(admin, stripe, url, key);
  return {
    getOrder: payments.getOrder,
    getIntent: payments.getIntent,
    listRefunds: async (intentId) => {
      const refunds = [];
      for await (
        const refund of stripe.refunds.list({
          payment_intent: intentId,
          limit: 100,
        })
      ) refunds.push(refund);
      return refunds;
    },
    createRefund: async (intentId, orderId, reason) =>
      stripe.refunds.create({
        payment_intent: intentId,
        ...(reason === "duplicate" || reason === "fraudulent"
          ? { reason }
          : {}),
        metadata: { order_id: orderId },
      }, { idempotencyKey: `refund_${orderId}` }),
    recordRefund: async (order, refund, observedAt) => {
      const { data, error } = await admin.rpc("record_verified_refund", {
        p_order_id: order.id,
        p_intent_id: refund.payment_intent,
        p_refund_id: refund.id,
        p_amount_cents: refund.amount,
        p_currency: refund.currency,
        p_status: refund.status,
        p_created_at: new Date(refund.created * 1000).toISOString(),
        p_failure_reason: refund.failure_reason ?? null,
        p_observed_at: observedAt,
      });
      if (error || !data) {
        throw error ?? new Error("Refund record was not confirmed");
      }
      return data;
    },
    notify: async (orderId) => {
      try {
        const response = await fetch(
          `${url}/functions/v1/send-order-notification`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${key}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ order_id: orderId, status: "refunded" }),
          },
        );
        if (!response.ok) {
          console.error("Refund notification failed", orderId, response.status);
        }
      } catch (error) {
        console.error("Refund notification failed", orderId, error);
      }
    },
  };
}
