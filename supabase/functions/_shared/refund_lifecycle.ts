import type {
  PaymentIntentSnapshot,
  PaymentOrder,
} from "./payment_lifecycle.ts";

export type RefundSnapshot = {
  id: string;
  payment_intent: string | null;
  amount: number;
  currency: string;
  status: string | null;
  created: number;
  failure_reason?: string | null;
};
export type RefundResult = {
  refundId: string;
  refundStatus: string;
  amount: number;
  pendingAmount: number;
  newlyRefunded: boolean;
};
export interface RefundPort {
  getOrder(
    orderId: string | null,
    intentId?: string,
  ): Promise<PaymentOrder | null>;
  getIntent(id: string): Promise<PaymentIntentSnapshot>;
  listRefunds(intentId: string): Promise<RefundSnapshot[]>;
  createRefund(
    intentId: string,
    orderId: string,
    reason?: string,
  ): Promise<RefundSnapshot>;
  recordRefund(
    order: PaymentOrder,
    refund: RefundSnapshot,
    observedAt: string,
  ): Promise<RefundResult>;
  notify(orderId: string): Promise<void>;
}
const REFUNDABLE = new Set([
  "paid",
  "packing",
  "shipped",
  "delivered",
  "refunded",
]);
const REFUND_STATES = new Set([
  "pending",
  "requires_action",
  "succeeded",
  "failed",
  "canceled",
]);
function verifyPayment(order: PaymentOrder, intent: PaymentIntentSnapshot) {
  if (
    intent.id !== order.stripe_payment_intent_id ||
    intent.status !== "succeeded" ||
    intent.amount !== Math.round(Number(order.total) * 100) ||
    intent.currency !== "sgd" ||
    intent.metadata.order_id !== order.id ||
    (order.user_id !== null && intent.metadata.user_id !== order.user_id) ||
    !REFUNDABLE.has(order.status)
  ) {
    throw new Error(
      "Refund payment/order identity, amount, currency or status mismatch",
    );
  }
}
async function record(
  order: PaymentOrder,
  intent: PaymentIntentSnapshot,
  refunds: RefundSnapshot[],
  port: RefundPort,
  observedAt: string,
) {
  // Validate the entire list before writing any part of it.
  const seen = new Set<string>();
  let total = 0;
  for (const refund of refunds) {
    if (
      !refund.id || seen.has(refund.id) ||
      refund.payment_intent !== intent.id ||
      refund.currency !== intent.currency ||
      !Number.isSafeInteger(refund.amount) ||
      refund.amount <= 0 || refund.amount > intent.amount ||
      !Number.isSafeInteger(refund.created) || refund.created < 0 ||
      !REFUND_STATES.has(refund.status ?? "")
    ) throw new Error("Invalid Stripe refund snapshot");
    seen.add(refund.id);
    if (
      refund.status === "succeeded" || refund.status === "pending" ||
      refund.status === "requires_action"
    ) total += refund.amount;
  }
  if (total > intent.amount) throw new Error("Refund total exceeds payment");
  let result: RefundResult | null = null;
  // Stripe lists newest first. Release terminal failures before recording
  // a successful replacement, otherwise the old pending reservation counts twice.
  const ordered = [...refunds].sort((a, b) =>
    Number(!["failed", "canceled"].includes(a.status ?? "")) -
    Number(!["failed", "canceled"].includes(b.status ?? ""))
  );
  for (const refund of ordered) {
    result = await port.recordRefund(order, refund, observedAt);
    if (result.newlyRefunded) await port.notify(order.id);
  }
  return result;
}
export async function requestOrderRefund(
  orderId: string,
  reason: string | undefined,
  port: RefundPort,
  refreshOnly = false,
): Promise<RefundResult> {
  const order = await port.getOrder(orderId);
  if (!order?.stripe_payment_intent_id) {
    throw new Error("Order has no Stripe payment to refund");
  }
  const intent = await port.getIntent(order.stripe_payment_intent_id);
  verifyPayment(order, intent);
  // Reconcile Stripe first, including a create whose response was lost more
  // than 24 hours ago (Stripe may have expired its idempotency cache).
  const observedAt = new Date().toISOString();
  let refunds = await port.listRefunds(intent.id);
  if (refunds.length === 0) {
    if (refreshOnly) {
      throw new Error(
        "No Stripe refund found. Check Stripe before taking further action",
      );
    }
    if (order.status === "refunded") {
      throw new Error("Refunded order requires manual reconciliation");
    }
    refunds = [await port.createRefund(intent.id, order.id, reason)];
  }
  // Existing failed/partial refunds require deliberate Dashboard handling.
  // A retry of this endpoint only refreshes them, never moves money again.
  const result = await record(order, intent, refunds, port, observedAt);
  if (!result) throw new Error("No Stripe refund returned");
  return result;
}
export async function syncOrderRefunds(
  intentId: string,
  port: RefundPort,
): Promise<RefundResult | null> {
  const intent = await port.getIntent(intentId);
  const order = await port.getOrder(intent.metadata.order_id || null, intentId);
  if (!order) return null;
  verifyPayment(order, intent);
  const observedAt = new Date().toISOString();
  return await record(
    order,
    intent,
    await port.listRefunds(intentId),
    port,
    observedAt,
  );
}
