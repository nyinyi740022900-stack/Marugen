export type PaymentOrder = {
  id: string;
  user_id: string | null;
  status: string;
  total: number;
  stripe_payment_intent_id: string | null;
};
export type PaymentIntentSnapshot = {
  id: string;
  status: string;
  amount: number;
  currency: string;
  metadata: Record<string, string>;
};
export interface PaymentPort {
  getOrder(
    orderId: string | null,
    intentId?: string,
  ): Promise<PaymentOrder | null>;
  getIntent(intentId: string): Promise<PaymentIntentSnapshot>;
  cancelIntent(intentId: string): Promise<PaymentIntentSnapshot>;
  transition(
    orderId: string,
    intentId: string | null,
    status: "paid" | "cancelled",
  ): Promise<boolean>;
  notify(orderId: string, status: "paid" | "cancelled"): Promise<void>;
}
const PAID_STATES = new Set([
  "paid",
  "packing",
  "shipped",
  "delivered",
  "refunded",
]);
function verify(
  order: PaymentOrder,
  intent: PaymentIntentSnapshot,
  intentId: string,
) {
  if (
    intent.id !== intentId || order.stripe_payment_intent_id !== intentId ||
    (intent.metadata.order_id && intent.metadata.order_id !== order.id) ||
    (order.user_id !== null && intent.metadata.user_id !== order.user_id) ||
    intent.amount !== Math.round(Number(order.total) * 100) ||
    intent.currency.toLowerCase() !== "sgd"
  ) {
    throw new Error("Payment/order identity, amount or currency mismatch");
  }
}
async function update(
  order: PaymentOrder,
  intentId: string | null,
  status: "paid" | "cancelled",
  port: PaymentPort,
) {
  const changed = await port.transition(order.id, intentId, status);
  if (changed) {
    await port.notify(order.id, status);
    return;
  }
  const latest = await port.getOrder(order.id);
  if (
    latest &&
    (latest.status === status ||
      (status === "paid" && PAID_STATES.has(latest.status)))
  ) return;
  throw new Error("Payment order changed; reconciliation required");
}
export async function applyPaymentEvent(
  type: string,
  intentId: string,
  port: PaymentPort,
): Promise<void> {
  // A failed attempt is retryable; its event can also arrive after success.
  if (type === "payment_intent.payment_failed") return;
  if (
    type !== "payment_intent.succeeded" && type !== "payment_intent.canceled"
  ) return;
  const intent = await port.getIntent(intentId);
  const order = await port.getOrder(intent.metadata.order_id || null, intentId);
  if (!order) throw new Error("Payment order not found; retry after linking");
  verify(order, intent, intentId);
  if (intent.status === "succeeded") {
    if (PAID_STATES.has(order.status)) return;
    if (order.status !== "pending") {
      throw new Error(
        "Paid payment has a terminal order; manual reconciliation required",
      );
    }
    await update(order, intentId, "paid", port);
  } else if (intent.status === "canceled") {
    if (order.status === "cancelled") return;
    if (order.status !== "pending") {
      throw new Error("Canceled payment conflicts with fulfilled order");
    }
    await update(order, intentId, "cancelled", port);
  } else if (type === "payment_intent.succeeded") {
    throw new Error("Success event does not match current Stripe state");
  }
}
export async function cancelPendingPayment(
  orderId: string,
  port: PaymentPort,
): Promise<void> {
  const order = await port.getOrder(orderId);
  if (!order) throw new Error("Order not found");
  if (order.status === "cancelled") return;
  if (order.status !== "pending") {
    throw new Error("Paid orders require a refund, not cancellation");
  }
  const id = order.stripe_payment_intent_id;
  if (!id) {
    await update(order, null, "cancelled", port);
    return;
  }
  const intent = await port.getIntent(id);
  verify(order, intent, id);
  if (intent.status === "succeeded") {
    await applyPaymentEvent("payment_intent.succeeded", id, port);
    throw new Error("Payment already succeeded; contact the shop for a refund");
  }
  if (intent.status === "processing" || intent.status === "requires_capture") {
    throw new Error(
      "Payment is processing; check its status before cancelling",
    );
  }
  const cancelled = intent.status === "canceled"
    ? intent
    : await port.cancelIntent(id);
  verify(order, cancelled, id);
  if (cancelled.status !== "canceled") {
    throw new Error("Stripe cancellation is not confirmed");
  }
  await update(order, id, "cancelled", port);
}

/** Recover a failed linking response without releasing potentially paid stock. */
export async function cleanupUnlinkedPayment(
  orderId: string,
  intentId: string,
  port: PaymentPort,
): Promise<void> {
  const order = await port.getOrder(orderId);
  if (!order) throw new Error("Cleanup order not found");
  if (
    order.stripe_payment_intent_id !== null &&
    order.stripe_payment_intent_id !== intentId
  ) throw new Error("Cleanup payment link changed");
  const intent = await port.getIntent(intentId);
  verify({ ...order, stripe_payment_intent_id: intentId }, intent, intentId);
  // Never assume a failed link response means the DB write did not commit.
  // Only Stripe's terminal cancellation authorizes releasing the reservation.
  const cancelled = intent.status === "canceled"
    ? intent
    : await port.cancelIntent(intentId);
  verify({ ...order, stripe_payment_intent_id: intentId }, cancelled, intentId);
  if (cancelled.status !== "canceled") {
    throw new Error("Cleanup cancellation unconfirmed");
  }
  const latest = await port.getOrder(orderId);
  if (!latest) throw new Error("Cleanup order disappeared");
  if (latest.status === "cancelled") return;
  if (
    latest.status !== "pending" ||
    (latest.stripe_payment_intent_id !== null &&
      latest.stripe_payment_intent_id !== intentId)
  ) throw new Error("Cleanup order changed; reconcile");
  await update(latest, latest.stripe_payment_intent_id, "cancelled", port);
}
export function completedCheckoutResponse(order: PaymentOrder) {
  if (!PAID_STATES.has(order.status)) return null;
  return {
    orderId: order.id,
    paymentIntentId: order.stripe_payment_intent_id,
    paymentStatus: order.status,
    clientSecret: null,
    amount: order.total,
    currency: "sgd",
  };
}
