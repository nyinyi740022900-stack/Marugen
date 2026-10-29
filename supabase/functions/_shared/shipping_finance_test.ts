import {
  bookingQuoteError,
  canonicalCheckout,
  cartWeightKg,
  normalizeRates,
  requireQuote,
  trustedParcel,
} from "./shipping_finance.ts";
import { manualCarrier } from "./delivery.ts";
function assert(v: unknown) {
  if (!v) throw new Error("assertion failed");
}
async function rejects(fn: () => unknown) {
  try {
    await fn();
  } catch {
    return;
  }
  throw new Error("Expected rejection");
}
const now = new Date("2026-10-19T10:00:00Z");
const raw = (name = "TracX Logis", currency = "SGD", amount = "4.05") => ({
  courier: { courier_name: name, service_id: "S1", courier_id: "T" },
  pricing: { currency, total_amount: amount },
});
Deno.test("observed EasyParcel legal name retains TracX service and SGD allocation", async () => {
  // Live nonbinding quote 2026-10-20: both Singapore routes returned this name.
  const quote = raw("TracX Logis Pte. Ltd", "MYR", "17.73");
  quote.courier.service_id = "EP-CS0GN";
  const rates = await normalizeRates(
    [quote, raw("J&T Express Singapore Pte Ltd")],
    async () => ({ rate: 0.3, date: "2026-10-19", source: "test FX" }),
    now,
  );
  assert(rates.length === 2 && rates[1].service_id === "EP-CS0GN");
  assert(
    rates[1].total_shipping_cents === 532 &&
      rates[1].buyer_shipping_cents === 266 &&
      rates[1].seller_shipping_cents === 266,
  );
});
Deno.test("all named couriers retain identity, SGD cents and seller rounding", async () => {
  const rates = await normalizeRates([
    raw(),
    raw("Qxpress"),
    raw("Other Track X Courier"),
    raw("Track X"),
  ], async () => {
    throw Error("no FX for SGD");
  }, now);
  assert(
    rates.length === 4 && rates.some((r) => r.carrier_name === "Qxpress") &&
      rates[0].total_shipping_cents === 405 &&
      rates[0].buyer_shipping_cents === 202 &&
      rates[0].seller_shipping_cents === 203,
  );
});
Deno.test("MYR quotes convert using fresh official FX and retain source", async () => {
  const rates = await normalizeRates(
    [raw("TracX Logis", "MYR", "13.49")],
    async () => ({ rate: 0.3, date: "2026-10-16", source: "Frankfurter/ECB" }),
    now,
  );
  assert(
    rates[0].total_shipping_cents === 405 &&
      rates[0].source_currency === "MYR" && rates[0].fx_rate === 0.3,
  );
  for (
    const fx of [{ rate: 0, date: "2026-10-19" }, {
      rate: 0.3,
      date: "2026-10-10",
    }, { rate: 0.3, date: "2026-10-20" }]
  ) {
    await rejects(() =>
      normalizeRates(
        [raw("Track X", "MYR")],
        async () => ({ ...fx, source: "ECB" }),
        now,
      )
    );
  }
  await rejects(() =>
    normalizeRates(
      [raw("Track X", "USD")],
      async () => ({ rate: 1, date: "2026-10-19", source: "ECB" }),
      now,
    )
  );
});
Deno.test("canonical checkout binds all items/address/promo regardless line ordering", () => {
  const a = {
    recipient_name: "A",
    phone: "81234567",
    line1: "1 Road",
    postal_code: "123456",
  };
  const c = [{ product_id: "a", quantity: 1 }, {
    product_id: "b",
    quantity: 2,
    variant_id: "v",
  }];
  assert(
    canonicalCheckout(c, a, " x ") ===
      canonicalCheckout([...c].reverse(), a, "X"),
  );
  assert(
    canonicalCheckout(c, a, "X") !==
      canonicalCheckout(c, { ...a, line1: "2 Road" }, "X"),
  );
});
Deno.test("quotes fail expired, mismatched user/cart or price profile", async () => {
  const q = {
    user_id: "U",
    checkout_signature: "C",
    pricing_signature: "P",
    expires_at: "2026-10-19T10:15:00Z",
  };
  requireQuote(q, "U", "C", "P", now);
  for (
    const patch of [{ user_id: "X" }, { checkout_signature: "X" }, {
      pricing_signature: "X",
    }, { expires_at: "2026-10-19T09:59:00Z" }]
  ) await rejects(() => requireQuote({ ...q, ...patch }, "U", "C", "P", now));
});
Deno.test("booking rejects legacy, changed parcel, wrong service/carrier and repricing before submit", () => {
  const p = {
    weight_kg: 1,
    length_cm: 20,
    width_cm: 10,
    height_cm: 10,
    collection_date: "2026-10-20",
  };
  const o = {
    shipping_quote_id: "Q",
    shipping_service_id: "S1",
    shipping_parcel: p,
    shipping_carrier_name: "TracX Logis",
    shipping_currency: "SGD",
    total_shipping_cents: 405,
    shipping_source_currency: "SGD",
    shipping_source_amount: 4.05,
  };
  const rate = {
    service_id: "S1",
    carrier_name: "TracX Logis",
    total_shipping_cents: 405,
    source_currency: "SGD",
    source_shipping_amount: 4.05,
  };
  assert(bookingQuoteError(o, "S1", p, rate) === null);
  for (
    const patch of [{ shipping_quote_id: null }, { shipping_service_id: "X" }, {
      shipping_carrier_name: "Other",
    }, { total_shipping_cents: 406 }]
  ) assert(bookingQuoteError({ ...o, ...patch }, "S1", p, rate));
  assert(bookingQuoteError(o, "S1", { ...p, weight_kg: 2 }, rate));
});
Deno.test("actual cart kg and optional dimensions quote; date derived server-side", async () => {
  const p = trustedParcel(2.5, {
    default_parcel_length_cm: 20,
    default_parcel_width_cm: 10,
    default_parcel_height_cm: 10,
  }, now);
  assert(p.collection_date === "2026-10-20");
  assert(trustedParcel(2.5, {}, now).weight_kg === 2.5);
  assert(trustedParcel(2.5, {}, now).length_cm === undefined);
  await rejects(() => trustedParcel(0, {}, now));
  assert(manualCarrier(undefined, null) === null);
  assert(manualCarrier(100030, null) === 100030);
  await rejects(() => manualCarrier(0, null));
});
Deno.test("idempotent checkout accepts equivalent fresh quote but rejects changed buyer fee or address", async () => {
  const { retryShippingError } = await import("./shipping_finance.ts");
  const existing = {
    shipping_checkout_signature: "C",
    shipping_quote_id: "Q",
    shipping_service_id: "S",
    shipping_carrier_name: "TracX Logis",
    total_shipping_cents: 405,
    buyer_shipping_cents: 202,
    seller_shipping_cents: 203,
  };
  const quote = {
    id: "NEW",
    checkout_signature: "C",
    service_id: "S",
    carrier_name: "TracX Logis",
    total_shipping_cents: 405,
    buyer_shipping_cents: 202,
    seller_shipping_cents: 203,
  };
  assert(retryShippingError(existing, "C", quote) === null);
  assert(retryShippingError(existing, "OTHER", quote));
  assert(
    retryShippingError(existing, "C", { ...quote, buyer_shipping_cents: 203 }),
  );
  assert(retryShippingError(existing, "C", null));
});
Deno.test("pickup may move to a later day without altering paid parcel or cost", () => {
  const p = {
    weight_kg: 1,
    length_cm: 20,
    width_cm: 10,
    height_cm: 10,
    collection_date: "2026-10-20",
  };
  const o = {
    shipping_quote_id: "Q",
    shipping_service_id: "S1",
    shipping_parcel: p,
    shipping_carrier_name: "TracX Logis",
    shipping_currency: "SGD",
    total_shipping_cents: 405,
    shipping_source_currency: "SGD",
    shipping_source_amount: 4.05,
  };
  const rate = {
    service_id: "S1",
    carrier_name: "TracX Logis",
    total_shipping_cents: 405,
    source_currency: "SGD",
    source_shipping_amount: 4.05,
  };
  assert(
    bookingQuoteError(
      o,
      "S1",
      { ...p, collection_date: "2026-10-22" },
      rate,
    ) === null,
  );
});
Deno.test("buyer shipping is added once after merchandise GST and shop delivery adds zero", async () => {
  const { checkoutAmountCents, bookingParcel } = await import(
    "./shipping_finance.ts"
  );
  assert(checkoutAmountCents(20, 202) === 2202);
  assert(checkoutAmountCents(21.8, 202) === 2382);
  assert(checkoutAmountCents(100, 0) === 10000);
  await rejects(() => checkoutAmountCents(20, -1));
  const old = {
    weight_kg: 1,
    length_cm: 20,
    width_cm: 10,
    height_cm: 10,
    collection_date: "2026-10-17",
  };
  assert(bookingParcel(old, null, now).collection_date === "2026-10-20");
  await rejects(() =>
    bookingParcel(
      old,
      { ...old, weight_kg: 2, collection_date: "2026-10-20" },
      now,
    )
  );
});
Deno.test("paid FX snapshot stays valid after five days while new MYR quotes reject stale rates", async () => {
  const old = async () => ({
    rate: .3,
    date: "2026-10-01",
    source: "Accepted ECB quote",
  });
  await rejects(() =>
    normalizeRates([raw("Track X", "MYR", "13.49")], old, now)
  );
  const rates = await normalizeRates(
    [raw("Track X", "MYR", "13.49")],
    old,
    now,
    {
      acceptedSnapshot: true,
    },
  );
  assert(rates[0].total_shipping_cents === 405);
});
Deno.test("exclusive GST uses integer-cent half rounding consistently with checkout", async () => {
  const { checkoutMerchandiseCents } = await import("./shipping_finance.ts");
  assert(checkoutMerchandiseCents(30.50, 0, 9, false) === 3325);
  assert(checkoutMerchandiseCents(9.95, .995, 9, true) === 895);
  assert(
    checkoutMerchandiseCents(20.05, 2.0050000000000003, 9, false) === 1966,
  );
});

Deno.test("cart kg uses trusted selected SKU weight times quantity and fails closed", async () => {
  const products = [{ id: "p", shipping_weight_kg: 3 }];
  const variants = [{ id: "v", product_id: "p", shipping_weight_kg: 0.5 }];
  assert(
    cartWeightKg(
      [{ product_id: "p", quantity: 2, variant_id: "v" }, {
        product_id: "p",
        quantity: 1,
      }],
      products,
      variants,
    ) === 4,
  );
  await rejects(() =>
    cartWeightKg(
      [{ product_id: "p", quantity: 1, variant_id: "wrong" }],
      products,
      variants,
    )
  );
  await rejects(() =>
    cartWeightKg([{ product_id: "p", quantity: 1 }], [{ id: "p" }], [])
  );
  await rejects(() =>
    cartWeightKg(
      [{ product_id: "p", quantity: 1, variant_id: "v" }],
      products,
      [{ id: "v", product_id: "p" }],
    )
  );
});
Deno.test("weight-only accepted quote allows actual dimensions at booking but locks kg", async () => {
  const { bookingParcel } = await import("./shipping_finance.ts");
  const accepted = { weight_kg: 2, collection_date: "2026-10-20" };
  const packed = { ...accepted, length_cm: 20, width_cm: 10, height_cm: 10 };
  assert(bookingParcel(accepted, packed, now).length_cm === 20);
  await rejects(() =>
    bookingParcel(accepted, { ...packed, weight_kg: 3 }, now)
  );
});

Deno.test("a non-TracX paid service books only with its exact accepted identity and price", () => {
  const p = {
    weight_kg: 1,
    length_cm: 10,
    width_cm: 10,
    height_cm: 10,
    collection_date: "2026-10-20",
  };
  const o = {
    shipping_quote_id: "Q",
    shipping_service_id: "J1",
    shipping_parcel: p,
    shipping_carrier_name: "J&T Express Singapore Pte Ltd",
    shipping_currency: "SGD",
    total_shipping_cents: 405,
    shipping_source_currency: "SGD",
    shipping_source_amount: 4.05,
  };
  const r = {
    service_id: "J1",
    carrier_name: o.shipping_carrier_name,
    total_shipping_cents: 405,
    source_currency: "SGD",
    source_shipping_amount: 4.05,
  };
  assert(bookingQuoteError(o, "J1", p, r) === null);
  assert(bookingQuoteError(o, "J1", p, { ...r, carrier_name: "Other" }));
});
Deno.test("checkout distinguishes door-to-door services from collection-point services", async () => {
  const pickup = {
    ...raw("J&T Express"),
    courier: {
      ...raw("J&T Express").courier,
      service_tag: [{ name: "Service Methods", value: "Pick Up from Door" }, {
        name: "Service Methods",
        value: "Deliver to Door",
      }],
    },
  };
  const point = {
    ...raw("Park N Parcel"),
    courier: {
      ...raw("Park N Parcel").courier,
      service_tag: [{ name: "Service Methods", value: "Drop Off to Point" }, {
        name: "Service Methods",
        value: "Deliver to Point",
      }],
    },
  };
  const rates = await normalizeRates([pickup, point], async () => {
    throw Error("No FX");
  }, now);
  assert(
    (rates.find((r) => r.carrier_name === "J&T Express") as unknown as Record<
      string,
      unknown
    >)?.door_to_door === true,
  );
  assert(
    (rates.find((r) => r.carrier_name === "Park N Parcel") as unknown as Record<
      string,
      unknown
    >)?.door_to_door === false,
  );
});
