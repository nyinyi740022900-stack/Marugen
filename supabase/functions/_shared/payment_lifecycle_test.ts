import {
  applyPaymentEvent,
  cancelPendingPayment,
  cleanupUnlinkedPayment,
  completedCheckoutResponse,
  type PaymentOrder,
  type PaymentPort,
} from "./payment_lifecycle.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
function fixture() {
  let order: PaymentOrder = {
    id: "o",
    user_id: "u",
    status: "pending",
    total: 20,
    stripe_payment_intent_id: "pi",
  };
  const intent: any = {
    id: "pi",
    status: "succeeded",
    amount: 2000,
    currency: "sgd",
    metadata: { order_id: "o", user_id: "u" },
  };
  let cancelled = 0, notifications = 0;
  const port: PaymentPort = {
    getOrder: async () => ({ ...order }),
    getIntent: async () => ({ ...intent }),
    cancelIntent: async () => {
      cancelled++;
      intent.status = "canceled";
      return { ...intent };
    },
    transition: async (_id, _pi, next) => {
      if (order.status !== "pending") return false;
      order.status = next;
      return true;
    },
    notify: async () => {
      notifications++;
    },
  };
  return {
    port,
    intent,
    get order() {
      return order;
    },
    get cancelled() {
      return cancelled;
    },
    get notifications() {
      return notifications;
    },
  };
}
Deno.test("failed attempts never cancel retryable or paid orders", async () => {
  const f = fixture();
  f.intent.status = "requires_payment_method";
  await applyPaymentEvent("payment_intent.payment_failed", "pi", f.port);
  assert(f.order.status === "pending", "retry reservation lost");
  f.intent.status = "succeeded";
  await applyPaymentEvent("payment_intent.succeeded", "pi", f.port);
  await applyPaymentEvent("payment_intent.payment_failed", "pi", f.port);
  assert(f.order.status === "paid", "paid order cancelled");
  assert(f.notifications === 1, "duplicate notification");
});
Deno.test("duplicate success is idempotent and mismatched amounts fail closed", async () => {
  const f = fixture();
  await applyPaymentEvent("payment_intent.succeeded", "pi", f.port);
  await applyPaymentEvent("payment_intent.succeeded", "pi", f.port);
  assert(f.notifications === 1, "duplicate paid notification");
  const bad = fixture();
  bad.intent.amount = 1;
  let threw = false;
  try {
    await applyPaymentEvent("payment_intent.succeeded", "pi", bad.port);
  } catch {
    threw = true;
  }
  assert(threw && bad.order.status === "pending", "amount mismatch accepted");
});
Deno.test("currency/metadata/PI mismatch and late success after cancellation are explicit errors", async () => {
  for (
    const change of [
      (f: any) => f.intent.currency = "usd",
      (f: any) => f.intent.metadata.user_id = "other",
      (f: any) => f.intent.id = "other",
      (f: any) => f.order.status = "cancelled",
    ]
  ) {
    const f = fixture();
    change(f);
    let threw = false;
    try {
      await applyPaymentEvent("payment_intent.succeeded", "pi", f.port);
    } catch {
      threw = true;
    }
    assert(threw, "conflict silently acknowledged");
  }
});
Deno.test("cancellation verifies Stripe terminal state before releasing stock", async () => {
  const f = fixture();
  f.intent.status = "requires_payment_method";
  await cancelPendingPayment("o", f.port);
  assert(
    f.cancelled === 1 && f.order.status === "cancelled",
    "unpaid cancellation failed",
  );
  const paid = fixture();
  let threw = false;
  try {
    await cancelPendingPayment("o", paid.port);
  } catch {
    threw = true;
  }
  assert(
    threw && paid.order.status === "paid" && paid.cancelled === 0,
    "paid cancellation released stock",
  );
  const processing = fixture();
  processing.intent.status = "processing";
  threw = false;
  try {
    await cancelPendingPayment("o", processing.port);
  } catch {
    threw = true;
  }
  assert(
    threw && processing.order.status === "pending",
    "processing cancelled",
  );
});
Deno.test("stale canceled event cannot regress paid state", async () => {
  const f = fixture();
  await applyPaymentEvent("payment_intent.succeeded", "pi", f.port);
  await applyPaymentEvent("payment_intent.canceled", "pi", f.port);
  assert(f.order.status === "paid", "canceled event regressed paid");
});

Deno.test("link cleanup never releases stock when Stripe cancellation fails", async () => {
  const f = fixture();
  f.intent.status = "processing";
  f.port.cancelIntent = async () => {
    throw new Error("Cancellation refused");
  };
  let rejected = false;
  try {
    await cleanupUnlinkedPayment("o", "pi", f.port);
  } catch {
    rejected = true;
  }
  assert(
    rejected && f.order.status === "pending",
    "unverified cleanup released stock",
  );
});
Deno.test("committed-link lost response cleanup safely cancels an unpaid intent", async () => {
  const f = fixture();
  f.intent.status = "requires_payment_method";
  await cleanupUnlinkedPayment("o", "pi", f.port);
  assert(
    f.cancelled === 1 && f.order.status === "cancelled",
    "verified cleanup failed",
  );
});
Deno.test("cleanup preserves succeeded/processing payments and rejects foreign links", async () => {
  for (const state of ["succeeded", "processing"]) {
    const f = fixture();
    f.intent.status = state;
    f.port.cancelIntent = async () => {
      throw new Error("Cannot cancel");
    };
    let rejected = false;
    try {
      await cleanupUnlinkedPayment("o", "pi", f.port);
    } catch {
      rejected = true;
    }
    assert(
      rejected && f.order.status === "pending",
      "possible paid stock released",
    );
  }
  const f = fixture();
  f.order.stripe_payment_intent_id = "other";
  let rejected = false;
  try {
    await cleanupUnlinkedPayment("o", "pi", f.port);
  } catch {
    rejected = true;
  }
  assert(rejected && f.cancelled === 0, "foreign intent cancelled");
});
Deno.test("completed checkout returns its known order rather than another client secret", () => {
  for (
    const status of ["paid", "packing", "shipped", "delivered", "refunded"]
  ) {
    const f = fixture();
    f.order.status = status;
    const result = completedCheckoutResponse(f.order);
    assert(
      result?.orderId === "o" && result.paymentStatus === status &&
        result.clientSecret === null,
      "paid retry not restored",
    );
  }
  const f = fixture();
  assert(
    completedCheckoutResponse(f.order) === null,
    "pending treated as completed",
  );
  f.order.status = "cancelled";
  assert(
    completedCheckoutResponse(f.order) === null,
    "cancelled key cannot restart",
  );
});
