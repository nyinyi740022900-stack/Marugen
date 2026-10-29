import { BookingRejectedError } from "./pickup_diagnostics.ts";
import {
  classifyFulfillment,
  courierEligibilityError,
  easyparcelOrderStatus,
  recoveryError,
  runBooking,
  validateParcel,
  validateSingaporeAddress,
} from "./delivery.ts";
function assert(value: unknown, message = "assertion failed") {
  if (!value) throw new Error(message);
}
function rejects(fn: () => unknown) {
  try {
    fn();
  } catch {
    return;
  }
  throw new Error("Expected rejection");
}
const paid = {
  status: "paid",
  fulfillment_method: "courier",
  tracking_registered: false,
  tracking_provider: null,
  items: [{ product_category: "fish_food" }],
};
Deno.test("live fish including mixed and deleted product snapshots stay shop delivered", () => {
  assert(
    classifyFulfillment([{ product_category: "koi" }, {
      product_category: "accessories",
    }]) === "shop_delivery",
  );
  assert(
    classifyFulfillment([{ product_category: "arowana", product_id: null }]) ===
      "shop_delivery",
  );
  assert(
    classifyFulfillment([{
      product_category: "fish_food",
      product_id: null,
    }]) === "courier",
  );
});
Deno.test("missing or unrecognized legacy categories fail closed", () => {
  for (
    const items of [[], [{}], [{ product_category: "unknown" }], [{
      product_category: "fish_food",
    }, {}]]
  ) {
    assert(classifyFulfillment(items) === "review_required");
    assert(courierEligibilityError({ ...paid, items }) !== null);
  }
});
Deno.test("only paid or packing courier orders can be quoted or claimed", () => {
  for (
    const status of ["pending", "shipped", "delivered", "cancelled", "refunded"]
  ) assert(courierEligibilityError({ ...paid, status }));
  assert(courierEligibilityError(paid) === null);
  assert(courierEligibilityError({ ...paid, status: "packing" }) === null);
  assert(
    courierEligibilityError({ ...paid, fulfillment_method: "shop_delivery" }),
  );
  assert(
    courierEligibilityError({
      ...paid,
      tracking_provider: "easyparcel",
      tracking_registered: true,
    }),
  );
});
Deno.test("only explicit collected codes advance paid/packing; delivered can skip a missed collection", () => {
  for (const code of [0, 2, 6, 7, 8, 9, 12, 99, undefined]) {
    assert(easyparcelOrderStatus("paid", code) === null);
  }
  for (const code of [3, 4, 11]) {
    assert(easyparcelOrderStatus("packing", code) === "shipped");
  }
  assert(easyparcelOrderStatus("paid", 5) === "delivered");
  assert(easyparcelOrderStatus("shipped", 5) === "delivered");
  for (const status of ["pending", "cancelled", "refunded", "delivered"]) {
    assert(easyparcelOrderStatus(status, 5) === null);
  }
});
Deno.test("parcel requires explicit positive dimensions, weight and valid future Singapore date", () => {
  const parcel = {
    weight_kg: 2,
    length_cm: 20,
    width_cm: 10,
    height_cm: 15,
    collection_date: "2026-10-20",
  };
  assert(
    validateParcel(parcel, new Date("2026-10-19T10:00:00Z")).length_cm === 20,
  );
  for (
    const input of [
      { ...parcel, weight_kg: 0 },
      { ...parcel, width_cm: NaN },
      { ...parcel, height_cm: undefined },
      { ...parcel, length_cm: "5" },
      { ...parcel, collection_date: "2026-02-30" },
      { ...parcel, collection_date: "2026-10-19" },
    ]
  ) rejects(() => validateParcel(input, new Date("2026-10-19T10:00:00Z")));
});
Deno.test("Singapore shipment addresses require a recipient, local phone, street and six-digit postcode", () => {
  const address = {
    recipient_name: "Customer",
    phone: "+65 8123 4567",
    line1: "1 Fish Road",
    postal_code: "123456",
  };
  assert(validateSingaporeAddress(address).phone === "81234567");
  for (
    const patch of [{ phone: "123" }, { postal_code: "12345" }, { line1: "" }, {
      recipient_name: "",
    }, { country: "MY" }]
  ) rejects(() => validateSingaporeAddress({ ...address, ...patch }));
});
Deno.test("recovery keeps an existing EasyParcel claim and cannot overwrite tracking or resurrect terminal orders", () => {
  const order = {
    ...paid,
    tracking_registered: true,
    tracking_provider: "easyparcel",
    easyparcel_booking_state: "needs_attention",
    qxpress_tracking_no: null,
  };
  assert(recoveryError(order, "AWB123", true) === null);
  assert(recoveryError(order, "AWB123", false));
  assert(
    recoveryError(
      { ...order, tracking_provider: "seventeentrack" },
      "AWB123",
      true,
    ),
  );
  assert(
    recoveryError({ ...order, qxpress_tracking_no: "OTHER" }, "AWB123", true),
  );
  assert(recoveryError({ ...order, status: "cancelled" }, "AWB123", true));
});
Deno.test("booking persistence failure preserves claim and records attention without retrying provider", async () => {
  let calls = 0, attention = 0;
  const result = await runBooking({
    claim: async () => true,
    submit: async () => {
      calls++;
      return { trackingNumber: "AWB", shipmentId: "SHIP", awbUrl: null };
    },
    persist: async () => {
      throw new Error("db unavailable");
    },
    attention: async () => {
      attention++;
    },
  });
  assert(
    result.ok === false && result.needsAttention === true && calls === 1 &&
      attention === 1,
  );
});
Deno.test("ambiguous provider failure keeps claim; failed atomic claim makes no provider call", async () => {
  let submits = 0, attention = 0;
  const port = {
    claim: async () => false,
    submit: async () => {
      submits++;
      throw new Error("timeout");
    },
    persist: async () => {},
    attention: async () => {
      attention++;
    },
  };
  assert((await runBooking(port)).ok === false && submits === 0);
  await runBooking({ ...port, claim: async () => true });
  assert(submits === 1 && attention === 1);
});
Deno.test("manual registration requires staff physical-handover attestation and does not bypass provider ownership", async () => {
  const { manualRegistrationError } = await import("./delivery.ts");
  assert(manualRegistrationError(paid, false));
  assert(manualRegistrationError(paid, true) === null);
  assert(
    manualRegistrationError({ ...paid, status: "shipped" }, true) === null,
  );
  assert(manualRegistrationError({ ...paid, status: "pending" }, true));
  assert(
    manualRegistrationError({
      ...paid,
      tracking_provider: "easyparcel",
      tracking_registered: true,
    }, true),
  );
});
Deno.test("reconciliation refuses an in-flight booking and accepts only a stale booking or attention state", () => {
  const order = {
    ...paid,
    tracking_provider: "easyparcel",
    tracking_registered: true,
    easyparcel_booking_state: "booking",
    easyparcel_booking_started_at: "2026-10-19T12:00:00Z",
  };
  assert(
    recoveryError(order, "AWB123", true, new Date("2026-10-19T12:01:00Z")),
  );
  assert(
    recoveryError(order, "AWB123", true, new Date("2026-10-19T12:16:00Z")) ===
      null,
  );
});
Deno.test("manual handover registration retry may only reuse the same saved 17TRACK number", async () => {
  const { manualRegistrationError } = await import("./delivery.ts");
  const registered = {
    ...paid,
    status: "shipped",
    tracking_provider: "seventeentrack",
    tracking_registered: true,
    qxpress_tracking_no: "AWB123",
  };
  assert(manualRegistrationError(registered, true, "AWB123") === null);
  assert(manualRegistrationError(registered, true, "OTHER"));
});
Deno.test("17TRACK verified delivery advances only shipped orders and ignores similar free text", async () => {
  const { seventeentrackOrderStatus } = await import("./delivery.ts");
  assert(seventeentrackOrderStatus("shipped", "Delivered") === "delivered");
  assert(seventeentrackOrderStatus("shipped", "Not Delivered") === null);
  for (
    const status of [
      "pending",
      "paid",
      "packing",
      "delivered",
      "cancelled",
      "refunded",
    ]
  ) assert(seventeentrackOrderStatus(status, "Delivered") === null);
});
Deno.test("manual registration preserves saved carrier and allows auto detection", async () => {
  const { manualCarrier } = await import("./delivery.ts");
  assert(manualCarrier(undefined, 100190) === 100190);
  assert(manualCarrier(null, 100190) === 100190);
  assert(manualCarrier(undefined, null) === null);
  assert(manualCarrier(100030, null) === 100030);
  rejects(() => manualCarrier("100030", null));
});

Deno.test("sample booking result needs attention and never confirms a live shipment", async () => {
  let submitted = 0;
  const result = await runBooking({
    claim: async () => true,
    submit: async () => {
      submitted++;
      return {
        trackingNumber: "EPSAMPLE123",
        shipmentId: "ES-123",
        awbUrl: null,
      };
    },
    persist: async () => {},
    attention: async () => {},
  });
  assert(result.ok === false && result.needsAttention === true);
  assert(submitted === 1);
});

Deno.test("explicit credit rejection is retained for owner diagnosis without retrying", async () => {
  let issue: string | null | undefined;
  let calls = 0;
  const result = await runBooking({
    claim: async () => true,
    submit: async () => {
      calls++;
      throw new BookingRejectedError("insufficient_credit");
    },
    persist: async () => {},
    attention: async (_, reason) => {
      issue = reason;
    },
  });
  assert(!result.ok && result.needsAttention);
  assert(issue === "insufficient_credit");
  assert(calls === 1);
});
