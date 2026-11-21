// Request rules and fixed customer copy for create-payment-intent, kept apart
// from the handler so they can be tested without Stripe or a database.

export const IDEMPOTENCY_KEY_REQUIRED_MESSAGE =
  "This checkout could not be started. Update the app and try again.";
export const PAYMENT_START_FAILED_MESSAGE =
  "We couldn't start your payment. You have not been charged. Please try again.";
export const CHECKOUT_FAILED_MESSAGE =
  "Something went wrong starting your checkout. Please try again.";

// The app sends 32 hex characters; any opaque token of a sane size is
// accepted so a future client can change how it generates the key.
const IDEMPOTENCY_KEY = /^[A-Za-z0-9_-]{8,128}$/;

/** The client's per-attempt checkout key, or null when missing or malformed. */
export function parseIdempotencyKey(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const key = value.trim();
  return IDEMPOTENCY_KEY.test(key) ? key : null;
}

/**
 * Stripe idempotency key for the order's single PaymentIntent. Derived from
 * the order id alone: the order row already fixes the amount and currency, and
 * a new checkout attempt always gets a new order.
 */
export function paymentIntentIdempotencyKey(orderId: string): string {
  if (!orderId) throw new Error("Order id required for the payment key");
  return `create_pi_${orderId}`;
}
