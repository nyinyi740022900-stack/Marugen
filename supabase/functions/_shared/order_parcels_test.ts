import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cheapestPickupRate,
  parcelTrackingState,
  runParcelBookings,
  validateAllocation,
} from "./order_parcels.ts";
const box = (items: unknown[]) => ({
  items,
  weight_kg: 1,
  length_cm: 10,
  width_cm: 10,
  height_cm: 10,
  collection_date: "2099-01-01",
});
Deno.test("allocation requires exact ordered quantities and rejects duplicate, foreign and missing lines", () => {
  const lines = [{ id: "a", quantity: 2 }, { id: "b", quantity: 1 }];
  assertEquals(
    validateAllocation(lines, [
      box([{ order_item_id: "a", quantity: 1 }]),
      box([{ order_item_id: "a", quantity: 1 }, {
        order_item_id: "b",
        quantity: 1,
      }]),
    ]).length,
    2,
  );
  for (
    const plan of [[
      box([{ order_item_id: "a", quantity: 2 }]),
      box([{ order_item_id: "foreign", quantity: 1 }]),
    ], [
      box([{ order_item_id: "a", quantity: 1 }]),
      box([{ order_item_id: "b", quantity: 1 }]),
    ], [
      box([{ order_item_id: "a", quantity: 1 }, {
        order_item_id: "a",
        quantity: 1,
      }]),
      box([{ order_item_id: "b", quantity: 1 }]),
    ]]
  ) assertThrows(() => validateAllocation(lines, plan));
});
Deno.test("cheapest quote excludes dropoff and pickup MOQ above one", () => {
  const rate = (id: string, total: number, door = true, moq = 1) => ({
    service_id: id,
    total_shipping_cents: total,
    door_to_door: door,
    pickup_minimum: moq,
  });
  assertEquals(
    cheapestPickupRate([
      rate("drop", 1, false),
      rate("bulk", 2, true, 5),
      rate("single", 500),
      rate("other", 600),
    ]).service_id,
    "single",
  );
  assertThrows(() => cheapestPickupRate([rate("bulk", 2, true, 5)]));
});
Deno.test("whole-plan claim precedes all submits and partial failure retains successful labels without retry", async () => {
  const events: string[] = [];
  const saved: Record<string, unknown>[] = [];
  await runParcelBookings([{ id: "a" }, { id: "b" }, { id: "c" }], {
    claim: async () => {
      events.push("claim");
      return true;
    },
    submit: async (p) => {
      events.push(p.id);
      if (p.id === "b") throw Error("uncertain");
      return {
        trackingNumber: "LIVE",
        shipmentId: "S",
        awbUrl: "https://label",
      };
    },
    persist: async (p, result) => {
      saved.push({ id: p.id, ...result });
    },
  });
  assertEquals(events, ["claim", "a", "b"]);
  assertEquals(saved.map((s) => s.state), [
    "booked",
    "needs_attention",
    "needs_attention",
  ]);
  await assertRejects(() =>
    runParcelBookings([{ id: "a" }], {
      claim: async () => false,
      submit: async () => {
        throw Error("must not submit");
      },
      persist: async () => {},
    })
  );
});
Deno.test("two booked parcels retain distinct carrier labels and tracking identities", async () => {
  const saved: Record<string, unknown>[] = [];
  await runParcelBookings([{ id: "box-1" }, { id: "box-2" }], {
    claim: async () => true,
    submit: async (parcel) => ({
      trackingNumber: `AWB-${parcel.id}`,
      shipmentId: `SHIP-${parcel.id}`,
      awbUrl: `https://carrier.example/label-${parcel.id}.pdf`,
    }),
    persist: async (parcel, result) => { saved.push({ id: parcel.id, ...result }); },
  });
  assertEquals(saved.map((p) => [p.id, p.tracking_number, p.awb_url]), [
    ["box-1", "AWB-box-1", "https://carrier.example/label-box-1.pdf"],
    ["box-2", "AWB-box-2", "https://carrier.example/label-box-2.pdf"],
  ]);
});
Deno.test("sample labels are quarantined and unpaid provider submissions require manual payment", async () => {
  for (
    const response of [{
      trackingNumber: "EPSAMPLE123",
      shipmentId: "S",
      awbUrl: "https://sample",
    }, {
      trackingNumber: null,
      shipmentId: "S",
      awbUrl: null,
      paymentRequired: true,
    }]
  ) {
    let saved: any;
    await runParcelBookings([{ id: "a" }], {
      claim: async () => true,
      submit: async () => response,
      persist: async (_, s) => {
        saved = s;
      },
    });
    assertEquals(
      saved.state,
      response.paymentRequired ? "payment_required" : "needs_attention",
    );
    assertEquals(saved.awb_url, null);
  }
});
Deno.test("only provider verified collection/delivery advances parcel state", () => {
  assertEquals(parcelTrackingState(7, "Scheduled"), "booked");
  assertEquals(parcelTrackingState(3, "Collected"), "collected");
  assertEquals(parcelTrackingState(5, "Delivered"), "delivered");
  assertEquals(parcelTrackingState(7, "Waiting payment"), "payment_required");
});
Deno.test("normalization preserves the provider's Pick Up MOQ constraint", async () => {
  const { normalizeRates } = await import("./shipping_finance.ts");
  const quotes = [{
    courier: {
      courier_name: "Carrier",
      service_id: "1",
      service_tag: [{ name: "Service Methods", value: "Pick Up from Door" }, {
        name: "Service Methods",
        value: "Deliver to Door",
      }, { name: "Pick Up MOQ", value: "5" }],
    },
    pricing: { currency: "SGD", total_amount: 3 },
  }];
  const rates = await normalizeRates(quotes, async () => {
    throw Error("SGD must not fetch FX");
  });
  assertEquals(rates[0].pickup_minimum, 5);
  assertThrows(() => cheapestPickupRate(rates));
});
Deno.test("fresh quotes require exact aggregate approval and unchanged signature for every box", async () => {
  const { assertParcelApproval } = await import("./order_parcels.ts");
  const parcels = [{
    quote_signature: "fresh",
    quote_expires_at: "2099-01-01T00:00:00Z",
  }, { quote_signature: "fresh", quote_expires_at: "2099-01-01T00:00:00Z" }];
  assertParcelApproval(parcels, "fresh", 1000, 1000, "fresh");
  assertThrows(() =>
    assertParcelApproval(parcels, "fresh", 1000, 999, "fresh")
  );
  assertThrows(() =>
    assertParcelApproval(parcels, "changed", 1000, 1000, "changed")
  );
  assertThrows(() =>
    assertParcelApproval(
      [{ quote_signature: "fresh", quote_expires_at: "2000-01-01T00:00:00Z" }],
      "fresh",
      1000,
      1000,
      "fresh",
    )
  );
});
Deno.test("persistence failure stops all later submits with claims retained", async () => {
  let submits = 0;
  await assertRejects(() =>
    runParcelBookings([{ id: "a" }, { id: "b" }], {
      claim: async () => true,
      submit: async () => {
        submits++;
        return { trackingNumber: "AWB", shipmentId: "S", awbUrl: null };
      },
      persist: async () => {
        throw Error("database unavailable");
      },
    })
  );
  assertEquals(submits, 1);
});
Deno.test("tracking identity requires actual provider AWB and shipment, never request echoes", async () => {
  const { assertParcelTrackingIdentity } = await import("./order_parcels.ts");
  const parcel = { tracking_number: "AWB", shipment_number: "SHIP" };
  assertParcelTrackingIdentity(parcel, {
    returnedNumber: "AWB",
    shipmentId: "SHIP",
  });
  assertThrows(() =>
    assertParcelTrackingIdentity(parcel, {
      returnedNumber: null,
      shipmentId: "SHIP",
    })
  );
  assertThrows(() =>
    assertParcelTrackingIdentity(parcel, {
      returnedNumber: "OTHER",
      shipmentId: "SHIP",
    })
  );
  assertThrows(() =>
    assertParcelTrackingIdentity(parcel, {
      returnedNumber: "AWB",
      shipmentId: null,
    })
  );
});
Deno.test("same-total replacement cannot reuse approval from a different viewed quote", async () => {
  const { assertParcelApproval } = await import("./order_parcels.ts");
  const current = [{
    quote_signature: "plan-B",
    quote_expires_at: "2099-01-01T00:00:00Z",
  }];
  assertThrows(() =>
    (assertParcelApproval as (...args: unknown[]) => void)(
      current,
      "plan-B",
      1000,
      1000,
      "plan-A",
    )
  );
});
Deno.test("recovery only accepts details for the existing shipment and real AWB", async () => {
  const { parcelRecoveryDetails } = await import("./order_parcels.ts");
  const p = { shipment_number: "SHIP", tracking_number: null };
  assertEquals(
    parcelRecoveryDetails(p, [{
      shipment_number: "OTHER",
      shipment_details: { awb_number: "AWB", awb_url: "https://label" },
    }]),
    null,
  );
  assertEquals(
    parcelRecoveryDetails(p, [{
      shipment_number: "SHIP",
      shipment_details: { awb_number: "EPSAMPLE123", awb_url: "https://label" },
    }]),
    null,
  );
  assertEquals(
    parcelRecoveryDetails(p, [{
      shipment_number: "SHIP",
      shipment_details: { awb_number: "AWB", awb_url: "https://label" },
    }]),
    { number: "AWB", awbUrl: "https://label" },
  );
  assertEquals(
    parcelRecoveryDetails({ ...p, tracking_number: "OLD" }, [{
      shipment_number: "SHIP",
      shipment_details: { awb_number: "AWB" },
    }]),
    null,
  );
});
Deno.test("selected variants never inherit disabled parent packing hints", async () => {
  const { parcelPackingHints } = await import("./order_parcels.ts");
  const product = {
    shipping_weight_kg: 4,
    packed_dimensions: { length_cm: 10, width_cm: 10, height_cm: 10 },
  };
  assertEquals(
    parcelPackingHints({
      variant_id: "variant",
      variant: { shipping_weight_kg: null, packed_dimensions: null },
      product,
    }),
    { weight_kg: null, packed_dimensions: null },
  );
  assertEquals(parcelPackingHints({ variant_id: null, product }), {
    weight_kg: 4,
    packed_dimensions: product.packed_dimensions,
  });
});
