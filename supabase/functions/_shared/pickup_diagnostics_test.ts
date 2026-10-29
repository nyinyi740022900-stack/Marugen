import {
  bookingFailureCode,
  checkPickup,
  diagnosePickup,
  readSgdWallet,
} from "./pickup_diagnostics.ts";
function eq(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
const order = {
  qxpress_tracking_no: "AWB123",
  easyparcel_shipment_id: "ES-123",
  easyparcel_booking_state: "booked",
};
Deno.test("sample identifiers never claim a live booking or wallet-caused delay", () => {
  eq(
    diagnosePickup({ ...order, qxpress_tracking_no: "EPSAMPLE123" }, {
      code: 7,
      text: "Schedule In Arrangement",
    }, "2026-10-22").reason,
    "sample_tracking",
  );
});
Deno.test("zero wallet alone never explains pickup; only provider unpaid status does", () => {
  eq(
    diagnosePickup(
      order,
      { code: 7, text: "Schedule In Arrangement" },
      "2026-10-22",
    ).reason,
    "awaiting_pickup",
  );
  eq(
    diagnosePickup(order, { code: null, text: "Waiting Payment" }, "2026-10-22")
      .reason,
    "payment_required",
  );
});
Deno.test("only fresh verified scheduled shipments with a past collection date are overdue", () => {
  eq(
    diagnosePickup(order, {
      code: 2,
      text: "To Be Collected",
      collectionDate: "2026-10-21 00:00:00",
    }, "2026-10-22").reason,
    "pickup_overdue",
  );
  eq(
    diagnosePickup(order, {
      code: 7,
      text: "Schedule In Arrangement",
      collectionDate: "2026-10-22 00:00:00",
    }, "2026-10-22").reason,
    "awaiting_pickup",
  );
  eq(diagnosePickup(order, null, "2026-10-22").reason, "unverified");
  eq(
    diagnosePickup(
      order,
      { code: 99, text: "New provider status" },
      "2026-10-22",
    ).reason,
    "unverified",
  );
});
Deno.test("collection, delivered, cancelled, returned and hold are distinct", () => {
  for (
    const [code, reason] of [
      [3, "collected"],
      [4, "collected"],
      [5, "delivered"],
      [11, "dropped_off"],
      [0, "cancelled"],
      [6, "returned"],
      [8, "on_hold"],
    ] as const
  ) eq(diagnosePickup(order, { code, text: "" }, "2026-10-22").reason, reason);
});
Deno.test("wallet displays only validated SGD amounts, never relabels MYR or NaN", () => {
  eq(readSgdWallet({ wallet: [{ currency: "MYR", balance: 99999 }] }), null);
  eq(
    readSgdWallet({
      wallet: [{ currency: "SGD", balance: "0.00" }],
      free_credit_wallet: [{ currency: "SGD", balance: 2 }],
    }),
    { balance: 0, free_credit: 2 },
  );
  eq(readSgdWallet({ wallet: [{ currency: "SGD", balance: "NaN" }] }), null);
});
Deno.test("diagnostics perform only wallet and shipment reads and verify identity", async () => {
  const urls: string[] = [];
  const fetcher = async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    urls.push(url);
    if (url.endsWith("/wallet")) {
      eq(init?.method, "GET");
      return Response.json({
        status_code: 200,
        data: { wallet: [{ currency: "SGD", balance: 0 }] },
      });
    }
    eq(url.endsWith("/shipment/details"), true);
    eq(JSON.parse(String(init?.body)), { shipment_number: "ES-123" });
    return Response.json({
      status_code: 200,
      data: [{
        shipment_number: "ES-123",
        shipment_details: {
          awb_number: "AWB123",
          shipment_status_code: 7,
          shipment_status: "Schedule In Arrangement",
          coll_date: "2026-10-20 00:00:00",
        },
      }],
    });
  };
  const result = await checkPickup(
    "secret",
    order,
    new Date("2026-10-22T12:00:00Z"),
    fetcher,
  );
  eq(result.reason, "pickup_overdue");
  eq(result.wallet?.balance, 0);
  eq(urls.length, 2);
  const mismatch = await checkPickup(
    "secret",
    order,
    new Date(),
    async () =>
      Response.json({
        status_code: 200,
        data: [{
          shipment_number: "OTHER",
          shipment_details: { shipment_status_code: 3 },
        }],
      }),
  );
  eq(mismatch.reason, "unverified");
});
Deno.test("provider outage is unknown, never an insufficient-balance diagnosis", async () => {
  const r = await checkPickup("secret", order, new Date(), async () => {
    throw new Error("offline");
  });
  eq(r.reason, "unverified");
  eq(r.wallet, null);
});

Deno.test("only explicit provider credit rejection becomes insufficient credit", () => {
  eq(bookingFailureCode({ message: "Request failed" }), null);
  eq(
    bookingFailureCode({
      data: [{ shipments: [{ errors: ["Insufficient credit"] }] }],
    }),
    "insufficient_credit",
  );
  eq(
    bookingFailureCode({
      data: [{
        shipments: [{ errors: ["The receiver postcode field is required"] }],
      }],
    }),
    "invalid_details",
  );
});

Deno.test("stored provider rejection survives without leaking raw error payloads", () => {
  eq(
    diagnosePickup(
      {
        ...order,
        easyparcel_booking_state: "needs_attention",
        tracking_status_detail: "booking_issue:insufficient_credit",
      },
      null,
      "2026-10-22",
    ).reason,
    "insufficient_credit",
  );
  eq(
    diagnosePickup(
      { ...order, tracking_status_detail: "balance zero" },
      null,
      "2026-10-22",
    ).reason,
    "unverified",
  );
});
Deno.test("sample diagnostic never calls a shipment API even if a sampled status claims collected", async () => {
  const paths: string[] = [];
  const result = await checkPickup(
    "secret",
    { ...order, qxpress_tracking_no: "EPSAMPLE123" },
    new Date(),
    async (input) => {
      paths.push(String(input));
      return Response.json({
        status_code: 200,
        data: { wallet: [{ currency: "SGD", balance: 0 }] },
      });
    },
  );
  eq(result.reason, "sample_tracking");
  eq(result.verified, false);
  eq(paths.length, 1);
  eq(paths[0].endsWith("/wallet"), true);
});

Deno.test("live provider account mismatch is explicit, not a credit assumption", async () => {
  const result = await checkPickup(
    "secret",
    order,
    new Date(),
    async (input) =>
      String(input).endsWith("/wallet")
        ? Response.json({
          status_code: 200,
          data: { wallet: [{ currency: "SGD", balance: 0 }] },
        })
        : Response.json({
          status_code: 400,
          message:
            "No Order with shipment_number ES-123 found from this account",
        }),
  );
  eq(result.reason, "not_found_in_account");
  eq(result.wallet?.balance, 0);
  eq(result.verified, false);
});
Deno.test("diagnostics tracking fallback uses newest carrier event instead of stale latest summary", async () => {
  const result = await checkPickup(
    "secret",
    { qxpress_tracking_no: "AWB123" },
    new Date("2026-10-24T12:00:00Z"),
    async (input) =>
      String(input).endsWith("/wallet")
        ? Response.json({ status_code: 200, data: {} })
        : Response.json({
          status_code: 200,
          data: {
            results: [{
              status: "success",
              awb_number: "AWB123",
              latest_shipment_status_code: 7,
              latest_tracking_status: "Schedule In Arrangement",
              latest_event_date: "2026-10-23T07:15:26.442Z",
              status_log: [{
                event_date: "2026-10-24 11:04:02",
                shipment_status_code: 3,
                tracking_status: "Pickup Done",
              }],
            }],
          },
        }),
  );
  eq(result.reason, "collected");
  eq(result.provider_status, "Pickup Done");
});
