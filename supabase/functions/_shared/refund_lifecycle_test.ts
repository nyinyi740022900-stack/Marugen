import {
  type RefundPort,
  requestOrderRefund,
  syncOrderRefunds,
} from "./refund_lifecycle.ts";

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
function fixture(status = "pending") {
  const records: any[] = [];
  const refunds: any[] = [];
  let creates = 0;
  const order = {
    id: "o",
    user_id: "u",
    status: "paid",
    total: 20,
    stripe_payment_intent_id: "pi",
  };
  const intent = {
    id: "pi",
    status: "succeeded",
    amount: 2000,
    currency: "sgd",
    metadata: { order_id: "o", user_id: "u" },
  };
  const port: RefundPort = {
    getOrder: async () => order,
    getIntent: async () => intent,
    listRefunds: async () => refunds,
    createRefund: async () => {
      creates++;
      const refund = {
        id: "re",
        payment_intent: "pi",
        amount: 2000,
        currency: "sgd",
        status,
        created: 100,
        failure_reason: null,
      };
      refunds.push(refund);
      return refund;
    },
    recordRefund: async (_order, refund) => {
      records.push({ ...refund });
      return {
        refundId: refund.id,
        refundStatus: refund.status!,
        amount: refund.status === "succeeded" ? 20 : 0,
        pendingAmount: refund.status === "pending" ? 20 : 0,
        newlyRefunded: refund.status === "succeeded",
      };
    },
    notify: async () => {},
  };
  return {
    port,
    order,
    intent,
    refunds,
    records,
    get creates() {
      return creates;
    },
  };
}

Deno.test("pending PayNow refund stays pending and a retry reuses it", async () => {
  const f = fixture();
  const first = await requestOrderRefund("o", undefined, f.port);
  assert(
    first.refundStatus === "pending" && first.amount === 0 &&
      first.pendingAmount === 20,
    "Pending refund must not claim money returned",
  );
  await requestOrderRefund("o", undefined, f.port);
  assert(f.creates === 1, "Retry must not create another refund");
});

Deno.test("lost create response is recovered by listing refunds, without a new charge", async () => {
  const f = fixture();
  const create = f.port.createRefund;
  f.port.createRefund = async (...args) => {
    await create(...args);
    throw new Error("response lost");
  };
  try {
    await requestOrderRefund("o", undefined, f.port);
  } catch (_) { /* simulated network loss */ }
  await requestOrderRefund("o", undefined, f.port);
  assert(
    f.creates === 1 && f.records.length === 1,
    "Must recover original refund",
  );
});

Deno.test("failed refund is recorded and never silently retried", async () => {
  const f = fixture("failed");
  const result = await requestOrderRefund("o", undefined, f.port);
  assert(
    result.refundStatus === "failed" && result.amount === 0,
    "Failure must be explicit",
  );
  await requestOrderRefund("o", undefined, f.port);
  assert(
    f.creates === 1,
    "Failed refund needs deliberate Dashboard action, not an automatic second refund",
  );
});

Deno.test("dashboard refund events sync current Stripe refunds including partial refunds", async () => {
  const f = fixture();
  f.refunds.push({
    id: "external",
    payment_intent: "pi",
    amount: 500,
    currency: "sgd",
    status: "succeeded",
    created: 100,
  });
  await syncOrderRefunds("pi", f.port);
  assert(
    f.records.length === 1 && f.records[0].amount === 500 && f.creates === 0,
    "Sync must record actual external refund without creating money movement",
  );
});

Deno.test("foreign payment, amount, currency and customer mismatches fail before refund creation", async () => {
  for (
    const change of [
      { id: "foreign" },
      { amount: 1000 },
      { currency: "usd" },
      { metadata: { order_id: "other", user_id: "u" } },
      { metadata: { order_id: "o", user_id: "other" } },
      { status: "processing" },
    ]
  ) {
    const f = fixture();
    Object.assign(f.intent, change);
    let rejected = false;
    try {
      await requestOrderRefund("o", undefined, f.port);
    } catch (_) {
      rejected = true;
    }
    assert(
      rejected && f.creates === 0 && f.records.length === 0,
      "Must reject identity mismatch before money movement",
    );
  }
});

Deno.test("invalid refund snapshots cannot update financial records", async () => {
  for (
    const change of [
      { payment_intent: "other" },
      { currency: "usd" },
      { amount: -1 },
      { amount: 2001 },
      { status: "unknown" },
    ]
  ) {
    const f = fixture();
    f.refunds.push({
      id: "re",
      payment_intent: "pi",
      amount: 2000,
      currency: "sgd",
      status: "pending",
      created: 100,
      ...change,
    });
    let rejected = false;
    try {
      await syncOrderRefunds("pi", f.port);
    } catch (_) {
      rejected = true;
    }
    assert(
      rejected && f.records.length === 0,
      "Invalid refund must fail closed",
    );
  }
});

Deno.test("unrelated Stripe payments are acknowledged without changing app orders", async () => {
  const f = fixture();
  f.port.getOrder = async () => null;
  assert(
    await syncOrderRefunds("pi", f.port) === null,
    "No app order means nothing to sync",
  );
  assert(f.records.length === 0 && f.creates === 0, "No financial writes");
});

Deno.test("failed reservations are released before newer replacement refunds are recorded", async () => {
  const f = fixture();
  let reserved = 2000;
  const record = f.port.recordRefund;
  f.port.recordRefund = async (order, refund, observedAt) => {
    if (refund.status === "failed") reserved = 0;
    if (refund.status === "succeeded" && reserved > 0) {
      throw new Error("Refunds exceed order total");
    }
    return await record(order, refund, observedAt);
  };
  f.refunds.push(
    {
      id: "new",
      payment_intent: "pi",
      amount: 2000,
      currency: "sgd",
      status: "succeeded",
      created: 200,
    },
    {
      id: "old",
      payment_intent: "pi",
      amount: 2000,
      currency: "sgd",
      status: "failed",
      created: 100,
    },
  );
  await syncOrderRefunds("pi", f.port);
  assert(
    f.records[0].id === "old" && f.records[1].id === "new",
    "Release failed reservations before replacements",
  );
});

Deno.test("refresh-only requests cannot create a refund even if no Stripe refund exists", async () => {
  const f = fixture();
  let rejected = false;
  try {
    await requestOrderRefund("o", undefined, f.port, true);
  } catch (_) {
    rejected = true;
  }
  assert(
    rejected && f.creates === 0,
    "Refreshing status must never move money",
  );
});
