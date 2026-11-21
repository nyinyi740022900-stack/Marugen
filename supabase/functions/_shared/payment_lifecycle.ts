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
  client_secret?: string | null;
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

/** True when the order's stored total is not the freshly computed amount. */
export function checkoutTotalChanged(
  storedTotal: unknown,
  freshAmountCents: number,
): boolean {
  const stored = Math.round(Number(storedTotal) * 100);
  // An unreadable amount on either side is not evidence of a change: the
  // existing order is then kept exactly as it is.
  if (
    storedTotal === null || storedTotal === "" ||
    !Number.isSafeInteger(stored) || !Number.isSafeInteger(freshAmountCents)
  ) return false;
  return stored !== freshAmountCents;
}

/**
 * Retires the pending order of an earlier attempt with the same checkout key
 * so a fresh order can replace it within the same request.
 *
 * "retired" is returned only once the order is `cancelled` in the database,
 * which the verified path (cancelPendingPayment, migration 0053) allows only
 * after Stripe has confirmed the PaymentIntent canceled. The cancellation
 * itself releases the reserved stock and promo slot, in the same statement.
 * Everything else is "kept": the payment succeeded or is processing, the
 * order has no PaymentIntent yet (another request is still creating it),
 * Stripe could not be reached, or the order changed meanwhile. The caller
 * must then answer with the existing order, unchanged.
 */
export async function retireStaleCheckout(
  orderId: string,
  userId: string,
  port: PaymentPort,
): Promise<"retired" | "kept"> {
  const order = await port.getOrder(orderId);
  if (!order || order.user_id !== userId) return "kept";
  if (order.status === "cancelled") return "retired";
  if (order.status !== "pending" || !order.stripe_payment_intent_id) {
    return "kept";
  }
  try {
    await cancelPendingPayment(orderId, port);
  } catch (error) {
    console.error("Stale checkout was not retired", orderId, error);
    return "kept";
  }
  // Trust the database, not the absence of an exception.
  const latest = await port.getOrder(orderId);
  return latest?.status === "cancelled" ? "retired" : "kept";
}

/**
 * What create-payment-intent does with the order an earlier request already
 * created for the same checkout key.
 *
 * "replace": the order was unpaid, today's server total for this request is
 * no longer its total, and it has been retired (see retireStaleCheckout).
 * The caller creates a fresh order; the old one no longer holds anything.
 * "reuse": answer with the existing order exactly as before. That is the
 * outcome whenever a change cannot be proven or the order cannot be retired
 * safely: it is paid, has no PaymentIntent yet, the total is unchanged, the
 * request cannot be priced right now (`freshAmountCents` returns null or
 * throws), or Stripe did not confirm the cancellation.
 *
 * `freshAmountCents` must price the request without counting what the
 * existing order itself reserves, and must not reserve anything.
 */
export async function repeatCheckoutAction(
  existing: PaymentOrder,
  userId: string,
  freshAmountCents: () => Promise<number | null>,
  port: PaymentPort,
): Promise<"reuse" | "replace"> {
  if (existing.status !== "pending" || !existing.stripe_payment_intent_id) {
    return "reuse";
  }
  let fresh: number | null = null;
  try {
    fresh = await freshAmountCents();
  } catch (error) {
    console.error(
      "Repeat checkout could not be repriced; keeping the order",
      existing.id,
      error,
    );
  }
  if (fresh === null || !checkoutTotalChanged(existing.total, fresh)) {
    return "reuse";
  }
  const outcome = await retireStaleCheckout(existing.id, userId, port);
  console.log("Repeat checkout total changed", existing.id, outcome);
  return outcome === "retired" ? "replace" : "reuse";
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
/** A resume request the customer can act on; `status` is the HTTP status. */
export class PaymentResumeError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}
const RESUMABLE_STATES = new Set([
  "requires_payment_method",
  "requires_confirmation",
  "requires_action",
]);
export type ResumedPayment = {
  orderId: string;
  paymentIntentId: string | null;
  clientSecret: string | null;
  amount: number;
  currency: string;
  amountCents?: number;
  paymentStatus?: string;
};
/**
 * Reopens the PaymentIntent of a customer's own pending order, so the order
 * page can offer "Complete payment" while its stock is still reserved.
 */
export async function resumePendingPayment(
  orderId: string,
  userId: string,
  port: PaymentPort,
): Promise<ResumedPayment> {
  const order = await port.getOrder(orderId);
  if (!order || order.user_id !== userId) {
    throw new PaymentResumeError("Order not found", 404);
  }
  const completed = completedCheckoutResponse(order);
  if (completed) return completed;
  const id = order.stripe_payment_intent_id;
  if (order.status !== "pending" || !id) {
    throw new PaymentResumeError(
      "This order can no longer be paid. Check out again from your cart.",
      409,
    );
  }
  const intent = await port.getIntent(id);
  verify(order, intent, id);
  if (intent.status === "succeeded") {
    await applyPaymentEvent("payment_intent.succeeded", id, port);
    return completedCheckoutResponse({ ...order, status: "paid" })!;
  }
  if (intent.status === "processing") {
    throw new PaymentResumeError(
      "Your payment is still processing. Check this order again shortly.",
      409,
    );
  }
  if (!RESUMABLE_STATES.has(intent.status) || !intent.client_secret) {
    throw new PaymentResumeError(
      "This order can no longer be paid. Check out again from your cart.",
      409,
    );
  }
  return {
    orderId: order.id,
    paymentIntentId: id,
    clientSecret: intent.client_secret,
    amount: order.total,
    amountCents: intent.amount,
    currency: intent.currency,
  };
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
