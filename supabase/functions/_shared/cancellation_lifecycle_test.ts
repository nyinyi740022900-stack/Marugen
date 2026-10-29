import { handleCancellation } from "./cancellation_lifecycle.ts";
import type { RefundPort } from "./refund_lifecycle.ts";
function assert(v: unknown, message: string) {
  if (!v) throw new Error(message);
}
function fixture(state = "requested", refundStatus = "pending") {
  let creates = 0;
  let decisions = 0;
  const request: any = { order_id: "o", user_id: "u", status: state };
  const refunds: any[] = [];
  const port: RefundPort = {
    getOrder: async () => ({
      id: "o",
      user_id: "u",
      status: "paid",
      total: 20,
      stripe_payment_intent_id: "pi",
    }),
    getIntent: async () => ({
      id: "pi",
      status: "succeeded",
      amount: 2000,
      currency: "sgd",
      metadata: { order_id: "o", user_id: "u" },
    }),
    listRefunds: async () => refunds,
    createRefund: async () => {
      creates++;
      const r = {
        id: "re",
        payment_intent: "pi",
        amount: 2000,
        currency: "sgd",
        status: refundStatus,
        created: 100,
      };
      refunds.push(r);
      return r;
    },
    recordRefund: async (_o, r) => ({
      refundId: r.id,
      refundStatus: r.status!,
      amount: 0,
      pendingAmount: 20,
      newlyRefunded: false,
    }),
    notify: async () => {},
  };
  return {
    request,
    port,
    refunds,
    get creates() {
      return creates;
    },
    get decisions() {
      return decisions;
    },
    transition: async (_id: string, _actor: string, action: string) => {
      decisions++;
      if (action === "approve") request.status = "approved";
      return { request: { ...request }, changed: true };
    },
  };
}
Deno.test("request and rejection never move money", async () => {
  const f = fixture();
  await handleCancellation("o", "u", "request", "reason", f);
  await handleCancellation("o", "a", "reject", "Cannot cancel", f);
  assert(f.creates === 0, "request/reject must never create refunds");
});
Deno.test("approval reserves hold before Stripe and retries existing pending refund", async () => {
  const f = fixture();
  const original = f.port.getIntent;
  f.port.getIntent = async (id) => {
    assert(f.request.status === "approved", "hold must commit before refund");
    return await original(id);
  };
  const first = await handleCancellation("o", "a", "approve", undefined, f);
  assert(
    first.refund?.refundStatus === "pending",
    "pending must remain pending",
  );
  await handleCancellation("o", "a", "approve", undefined, f);
  assert(f.creates === 1, "approval retry created duplicate refund");
});
Deno.test("failed and requires-action approval retries reconcile without another refund", async () => {
  for (const state of ["failed", "requires_action"]) {
    const f = fixture("requested", state);
    await handleCancellation("o", "a", "approve", undefined, f);
    const result = await handleCancellation("o", "a", "approve", undefined, f);
    assert(
      f.creates === 1 && result.refund?.refundStatus === state,
      "retry must reconcile existing refund",
    );
  }
});
Deno.test("lost Stripe response keeps approval and recovers without duplicate", async () => {
  const f = fixture();
  const create = f.port.createRefund;
  f.port.createRefund = async (...args) => {
    await create(...args);
    throw new Error("response lost");
  };
  const result = await handleCancellation("o", "a", "approve", undefined, f);
  assert(
    result.request.status === "approved" && result.refund_error,
    "approval must survive refund error",
  );
  await handleCancellation("o", "a", "approve", undefined, f);
  assert(f.creates === 1, "lost response retry must find original refund");
});
Deno.test("refresh cannot initiate a refund", async () => {
  const f = fixture("approved");
  const result = await handleCancellation("o", "a", "refresh", undefined, f);
  assert(
    f.creates === 0 && result.refund_error,
    "refresh must never move money",
  );
});
Deno.test("denied transition cannot reach Stripe", async () => {
  const f = fixture();
  f.transition = async () => {
    throw new Error("Forbidden");
  };
  let failed = false;
  try {
    await handleCancellation("o", "x", "approve", undefined, f);
  } catch {
    failed = true;
  }
  assert(failed && f.creates === 0, "authorization failure reached Stripe");
});
