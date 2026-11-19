import {
  CHECKOUT_FAILED_MESSAGE,
  IDEMPOTENCY_KEY_REQUIRED_MESSAGE,
  parseIdempotencyKey,
  PAYMENT_START_FAILED_MESSAGE,
  paymentIntentIdempotencyKey,
} from "./checkout_request.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
Deno.test("the app's checkout key is accepted and trimmed", () => {
  // checkout_screen.dart: 16 random bytes as 32 hex characters.
  const key = "0123456789abcdef0123456789abcdef";
  assert(parseIdempotencyKey(key) === key, "app key rejected");
  assert(parseIdempotencyKey(`  ${key} `) === key, "not trimmed");
  assert(
    parseIdempotencyKey("3f2c1b6e-8a4d-4c1e-9b7a-0d5e6f7a8b9c") !== null,
    "uuid-style key rejected",
  );
});
Deno.test("a missing or malformed checkout key is refused", () => {
  for (
    const bad of [
      undefined,
      null,
      "",
      "   ",
      "short",
      42,
      {},
      ["0123456789abcdef"],
      "a".repeat(129),
      "has spaces in the key",
      "drop'table;--",
    ]
  ) {
    assert(parseIdempotencyKey(bad) === null, `accepted ${JSON.stringify(bad)}`);
  }
});
Deno.test("the Stripe key is the same for one order and different for another", () => {
  const a = "c6610000-0000-0000-0000-000000000001";
  const b = "c6610000-0000-0000-0000-000000000002";
  assert(
    paymentIntentIdempotencyKey(a) === paymentIntentIdempotencyKey(a),
    "not stable",
  );
  assert(
    paymentIntentIdempotencyKey(a) !== paymentIntentIdempotencyKey(b),
    "orders share a key",
  );
  assert(paymentIntentIdempotencyKey(a).includes(a), "not derived from order");
  assert(paymentIntentIdempotencyKey(a).length <= 255, "over Stripe's limit");
  let threw = false;
  try {
    paymentIntentIdempotencyKey("");
  } catch {
    threw = true;
  }
  assert(threw, "an empty order id must never become a shared key");
});
Deno.test("customer copy carries no internal detail", () => {
  for (
    const copy of [
      IDEMPOTENCY_KEY_REQUIRED_MESSAGE,
      PAYMENT_START_FAILED_MESSAGE,
      CHECKOUT_FAILED_MESSAGE,
    ]
  ) {
    assert(
      copy.length > 0 && copy.length < 200 &&
        !/stripe|error:|sk_|postgres|idempotency/i.test(copy),
      copy,
    );
  }
});
