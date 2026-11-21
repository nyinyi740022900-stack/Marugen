// Repeat checkout key whose server total changed (create-payment-intent).
// The world below stands in for the database and Stripe with the same rules
// the real ones enforce: one live order per key (0054), a PaymentIntent that
// can only be canceled while unpaid, and stock/promo released exactly once
// in the statement that cancels the order (0077, 0069).
import {
  checkoutTotalChanged,
  type PaymentIntentSnapshot,
  type PaymentOrder,
  type PaymentPort,
  repeatCheckoutAction,
  retireStaleCheckout,
} from "./payment_lifecycle.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
const USER = "u";
const KEY = "key-1";
type Row = PaymentOrder & { key: string; holdsFish: boolean };
function world(intentStatus = "requires_payment_method") {
  const orders = new Map<string, Row>();
  const intents = new Map<string, PaymentIntentSnapshot>();
  const w = {
    orders,
    intents,
    fishAvailable: true,
    promoSlotsUsed: 0,
    stockReleases: 0,
    events: [] as string[],
    stripeDown: false,
    cancelFails: false,
    /** Runs just before Stripe processes a cancel (a race window). */
    beforeCancel: null as null | (() => void),
    /** The invariant the whole change must keep. */
    check() {
      const live = [...orders.values()].filter((o) =>
        o.status !== "cancelled" && o.holdsFish
      );
      assert(live.length <= 1, `fish held by ${live.length} live orders`);
      assert(
        w.fishAvailable === (live.length === 0),
        "stock does not match the live reservation",
      );
      assert(
        w.promoSlotsUsed === live.length,
        `promo slots ${w.promoSlotsUsed} for ${live.length} live orders`,
      );
      const keyed = [...orders.values()].filter((o) =>
        o.status !== "cancelled" && o.key === KEY
      );
      assert(keyed.length <= 1, "two live orders share one checkout key");
    },
    /** What create-payment-intent does after pricing: order, items, PI. */
    create(id: string, total: number): Row {
      if (
        [...orders.values()].some((o) =>
          o.key === KEY && o.status !== "cancelled"
        )
      ) throw Object.assign(new Error("unique violation"), { code: "23505" });
      if (!w.fishAvailable) throw new Error("already sold");
      w.fishAvailable = false;
      w.promoSlotsUsed++;
      const row: Row = {
        id,
        user_id: USER,
        status: "pending",
        total,
        stripe_payment_intent_id: `pi_${id}`,
        key: KEY,
        holdsFish: true,
      };
      orders.set(id, row);
      intents.set(row.stripe_payment_intent_id!, {
        id: row.stripe_payment_intent_id!,
        status: intentStatus,
        amount: Math.round(total * 100),
        currency: "sgd",
        metadata: { order_id: id, user_id: USER },
      });
      w.events.push(`create ${id}`);
      // A snapshot, like the row the handler's lookup returned.
      return { ...row };
    },
  };
  const port: PaymentPort = {
    getOrder: async (id) => {
      const row = id ? orders.get(id) : null;
      return row ? { ...row } : null;
    },
    getIntent: async (id) => {
      if (w.stripeDown) throw new Error("Stripe connection error");
      return { ...intents.get(id)! };
    },
    cancelIntent: async (id) => {
      if (w.stripeDown) throw new Error("Stripe connection error");
      w.beforeCancel?.();
      const intent = intents.get(id)!;
      if (["succeeded", "processing"].includes(intent.status)) {
        throw new Error(`cannot cancel a ${intent.status} PaymentIntent`);
      }
      if (!w.cancelFails) intent.status = "canceled";
      w.events.push(`stripe canceled=${intent.status === "canceled"}`);
      return { ...intent };
    },
    transition: async (id, intentId, status) => {
      const row = orders.get(id)!;
      if (
        row.status !== "pending" || row.stripe_payment_intent_id !== intentId
      ) return false;
      row.status = status;
      if (status === "cancelled") {
        // restore_stock_on_cancel / restore_promo_on_cancel, same statement.
        w.fishAvailable = true;
        w.promoSlotsUsed--;
        w.stockReleases++;
        w.events.push(`release ${id}`);
      }
      return true;
    },
    notify: async () => {},
  };
  return { w, port };
}
const freshly = (cents: number | null) => async () => cents;

Deno.test("a changed total retires the old attempt, then one fresh order holds the fish", async () => {
  const { w, port } = world();
  const old = w.create("old", 100);
  const action = await repeatCheckoutAction(old, USER, freshly(12000), port);
  assert(action === "replace", `expected replace, got ${action}`);
  assert(w.orders.get("old")!.status === "cancelled", "old order still live");
  assert(w.intents.get("pi_old")!.status === "canceled", "old PI still live");
  assert(w.stockReleases === 1, "stock not released exactly once");
  w.check();
  // Stripe confirmed the cancellation BEFORE the reservation was released.
  assert(
    w.events.join(" | ") ===
      "create old | stripe canceled=true | release old",
    `order of events: ${w.events.join(" | ")}`,
  );
  w.create("new", 120);
  w.check();
  assert(
    w.orders.get("new")!.status === "pending" && !w.fishAvailable,
    "fresh order did not reserve",
  );
});
Deno.test("an unchanged total reuses the order and touches nothing", async () => {
  const { w, port } = world();
  const old = w.create("old", 100);
  w.stripeDown = true; // any Stripe call would throw
  assert(
    await repeatCheckoutAction(old, USER, freshly(10000), port) === "reuse",
    "replaced an unchanged checkout",
  );
  assert(w.orders.get("old")!.status === "pending", "order changed");
  assert(w.stockReleases === 0, "stock released");
  w.check();
});
Deno.test("a processing or succeeded payment is never retired", async () => {
  for (const status of ["processing", "requires_capture", "succeeded"]) {
    const { w, port } = world(status);
    const old = w.create("old", 100);
    const action = await repeatCheckoutAction(old, USER, freshly(12000), port);
    assert(action === "reuse", `${status}: ${action}`);
    assert(w.stockReleases === 0, `${status}: stock released`);
    assert(
      w.intents.get("pi_old")!.status === status,
      `${status}: PaymentIntent was touched`,
    );
    assert(
      w.orders.get("old")!.status ===
        (status === "succeeded" ? "paid" : "pending"),
      `${status}: order is ${w.orders.get("old")!.status}`,
    );
    w.check();
    // The fish is still this order's: a second order cannot take it.
    let second = "";
    try {
      w.create("new", 120);
    } catch (error) {
      second = (error as Error).message;
    }
    assert(second !== "", `${status}: a second live order was created`);
    w.check();
  }
});
Deno.test("a payment that succeeds while the cancel is in flight keeps its order and stock", async () => {
  const { w, port } = world();
  const old = w.create("old", 100);
  w.beforeCancel = () => {
    w.intents.get("pi_old")!.status = "succeeded";
  };
  assert(
    await repeatCheckoutAction(old, USER, freshly(12000), port) === "reuse",
    "replaced an order whose payment succeeded",
  );
  assert(w.orders.get("old")!.status === "pending", "order was cancelled");
  assert(w.stockReleases === 0, "paid stock released");
  w.check();
});
Deno.test("an unconfirmed or unreachable Stripe cancellation keeps the order", async () => {
  const unconfirmed = world();
  const a = unconfirmed.w.create("old", 100);
  unconfirmed.w.cancelFails = true; // Stripe answers, but not `canceled`
  assert(
    await repeatCheckoutAction(a, USER, freshly(12000), unconfirmed.port) ===
      "reuse",
    "released stock without a confirmed cancellation",
  );
  assert(unconfirmed.w.stockReleases === 0, "stock released");
  unconfirmed.w.check();

  const down = world();
  const b = down.w.create("old", 100);
  down.w.stripeDown = true;
  assert(
    await repeatCheckoutAction(b, USER, freshly(12000), down.port) === "reuse",
    "released stock while Stripe was unreachable",
  );
  assert(down.w.orders.get("old")!.status === "pending", "order changed");
  down.w.check();
  // Once Stripe is back the same retry heals itself.
  down.w.stripeDown = false;
  assert(
    await repeatCheckoutAction(b, USER, freshly(12000), down.port) ===
      "replace",
    "did not recover",
  );
  assert(down.w.stockReleases === 1, "released more than once");
  down.w.check();
});
Deno.test("a request that cannot be priced keeps the order without contacting Stripe", async () => {
  const { w, port } = world();
  const old = w.create("old", 100);
  w.stripeDown = true;
  assert(
    await repeatCheckoutAction(old, USER, freshly(null), port) === "reuse",
    "replaced without a fresh total",
  );
  assert(
    await repeatCheckoutAction(old, USER, async () => {
      throw new Error("database unavailable");
    }, port) === "reuse",
    "replaced after a pricing failure",
  );
  assert(
    await repeatCheckoutAction(old, USER, freshly(Number.NaN), port) ===
      "reuse",
    "replaced on an unreadable amount",
  );
  w.check();
});
Deno.test("an order still being prepared, or already paid, is not repriced", async () => {
  const { w, port } = world();
  const old = w.create("old", 100);
  let priced = 0;
  const count = async () => {
    priced++;
    return 12000;
  };
  assert(
    await repeatCheckoutAction(
      { ...old, stripe_payment_intent_id: null },
      USER,
      count,
      port,
    ) === "reuse",
    "retired an order another request is still creating",
  );
  assert(
    await repeatCheckoutAction(
      { ...old, status: "paid" },
      USER,
      count,
      port,
    ) ===
      "reuse",
    "retired a paid order",
  );
  assert(priced === 0 && w.stockReleases === 0, "work was done");
  w.check();
});
Deno.test("only the owner's own unpaid order can be retired", async () => {
  const { w, port } = world();
  w.create("old", 100);
  assert(
    await retireStaleCheckout("old", "someone-else", port) === "kept",
    "retired another user's order",
  );
  assert(
    await retireStaleCheckout("missing", USER, port) === "kept",
    "retired a missing order",
  );
  assert(w.stockReleases === 0, "stock released");
  // A PaymentIntent that is not this order's (amount differs) fails closed.
  w.intents.get("pi_old")!.amount = 1;
  assert(
    await retireStaleCheckout("old", USER, port) === "kept",
    "retired on a payment/order mismatch",
  );
  assert(w.orders.get("old")!.status === "pending", "order changed");
  w.check();
});
Deno.test("two retries racing each other release once and create one order", async () => {
  const { w, port } = world();
  const old = w.create("old", 100);
  const actions = await Promise.all([
    repeatCheckoutAction(old, USER, freshly(12000), port),
    repeatCheckoutAction(old, USER, freshly(12000), port),
  ]);
  assert(
    actions.every((a) => a === "replace"),
    `actions: ${actions}`,
  );
  assert(w.stockReleases === 1, `released ${w.stockReleases} times`);
  w.check();
  // Both go on to create; the checkout key lets exactly one through and
  // the loser is answered with the winner's order (23505 handling).
  let created = 0, refused = 0;
  for (const id of ["new-a", "new-b"]) {
    try {
      w.create(id, 120);
      created++;
    } catch (error) {
      if ((error as { code?: string }).code === "23505") refused++;
    }
    w.check();
  }
  assert(
    created === 1 && refused === 1,
    `created ${created}, refused ${refused}`,
  );
});
Deno.test("an order already cancelled elsewhere counts as retired, with no second release", async () => {
  const { w, port } = world();
  const old = w.create("old", 100);
  // The client's own release (cancel-order) landed after the lookup.
  assert(await retireStaleCheckout("old", USER, port) === "retired", "first");
  assert(
    await repeatCheckoutAction(old, USER, freshly(12000), port) === "replace",
    "a cancelled order blocked the fresh checkout",
  );
  assert(w.stockReleases === 1, "stock released twice");
  w.check();
});
Deno.test("totals are compared in whole cents", () => {
  assert(!checkoutTotalChanged(20, 2000), "20 vs 2000");
  assert(!checkoutTotalChanged("19.99", 1999), "numeric string");
  assert(!checkoutTotalChanged(0.1 + 0.2, 30), "float noise");
  assert(!checkoutTotalChanged(1.15, 115), "1.15");
  assert(checkoutTotalChanged(20, 2001), "one cent more");
  assert(checkoutTotalChanged(20, 1999), "one cent less");
  // Unreadable amounts are never treated as a change.
  for (const stored of [null, undefined, "", "abc", Number.NaN]) {
    assert(!checkoutTotalChanged(stored, 2000), `stored ${stored}`);
  }
  for (const fresh of [Number.NaN, Infinity, 19.5]) {
    assert(!checkoutTotalChanged(20, fresh), `fresh ${fresh}`);
  }
});
