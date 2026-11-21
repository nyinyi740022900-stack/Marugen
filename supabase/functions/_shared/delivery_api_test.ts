import {
  DELIVERY_FAILED_MESSAGE,
  DeliveryError,
  deliveryFailure,
  failure,
  rpcError,
} from "./delivery_api.ts";
import { DeliveryValidationError } from "./delivery.ts";
import {
  EasyParcelNotConnectedError,
  EasyParcelRefreshError,
} from "./easyparcel_token.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
// What a failed PostgREST call hands back: an Error in current supabase-js,
// a plain object in older releases. Both carry the raw Postgres text.
function postgres(code: string, message: string) {
  return {
    asError: Object.assign(new Error(message), { code, details: "detail" }),
    asObject: { code, message, details: "detail", hint: null },
  };
}
const LEAKS = [
  postgres(
    "23505",
    'duplicate key value violates unique constraint "order_parcels_order_id_parcel_number_key"',
  ),
  postgres("22P02", 'invalid input syntax for type uuid: "jane@example.com"'),
  postgres("42501", "permission denied for table easyparcel_connection"),
  postgres("57014", "canceling statement due to statement timeout"),
];
Deno.test("authored delivery errors reach staff with their own status", () => {
  const cases: [unknown, string, number][] = [
    [new DeliveryError("Order not found", 404), "Order not found", 404],
    [new DeliveryError("order_id is required"), "order_id is required", 400],
    [
      new DeliveryValidationError("Each box needs ordered items"),
      "Each box needs ordered items",
      400,
    ],
    [
      new EasyParcelNotConnectedError(),
      "EasyParcel is not connected. Connect it from Settings first.",
      409,
    ],
    [
      new EasyParcelRefreshError("Try again in a moment."),
      "Try again in a moment.",
      503,
    ],
  ];
  for (const [error, message, status] of cases) {
    const result = deliveryFailure(error);
    assert(
      result.authored && result.message === message &&
        result.status === status,
      `lost authored message: ${JSON.stringify(result)}`,
    );
  }
});
Deno.test("database, provider and unknown errors become fixed copy", async () => {
  const unsafe: unknown[] = [
    ...LEAKS.flatMap((l) => [l.asError, l.asObject]),
    new Error("connect ECONNREFUSED 10.1.2.3:5432"),
    new TypeError("Cannot read properties of undefined (reading 'unit_price')"),
    new SyntaxError("Unexpected token < in JSON at position 0"),
    Object.assign(new Error("The operation timed out"), {
      name: "TimeoutError",
    }),
    "sk_live_string_thrown_by_mistake",
    null,
    undefined,
  ];
  for (const error of unsafe) {
    const result = deliveryFailure(error);
    assert(
      !result.authored && result.message === DELIVERY_FAILED_MESSAGE &&
        result.status === 500,
      `leaked: ${JSON.stringify(result)}`,
    );
    const response = failure(error, "[test]");
    const body = await response.json();
    assert(response.status === 500, `status ${response.status}`);
    assert(
      JSON.stringify(body) ===
        JSON.stringify({ error: DELIVERY_FAILED_MESSAGE }),
      `response leaked: ${JSON.stringify(body)}`,
    );
  }
});
Deno.test("failure() answers authored errors with their message and status", async () => {
  const response = failure(
    new DeliveryError("Parcel not found", 404),
    "[test]",
  );
  assert(response.status === 404, "status");
  assert((await response.json()).error === "Parcel not found", "message");
});
Deno.test("only our own raise exception (P0001) passes from an RPC failure", () => {
  const rule = rpcError({
    code: "P0001",
    message: "Fresh quote and exact owner approval required",
  });
  assert(
    rule instanceof DeliveryError && rule.status === 409 &&
      rule.message === "Fresh quote and exact owner approval required",
    "business rule lost",
  );
  assert(
    (rpcError(
      { code: "P0001", message: "No parcel plan to reset" },
      404,
    ) as DeliveryError).status === 404,
    "status override ignored",
  );
  for (const leak of LEAKS) {
    for (const raw of [leak.asError, leak.asObject]) {
      const passed = rpcError(raw);
      assert(passed === raw, "raw error was rewrapped");
      assert(
        deliveryFailure(passed).message === DELIVERY_FAILED_MESSAGE,
        `raw database text passed: ${raw.message}`,
      );
    }
  }
  // An RPC error with no code or an empty message is never authored copy.
  for (const odd of [{ message: "boom" }, { code: "P0001", message: "" }, {}]) {
    assert(
      !(rpcError(odd) instanceof DeliveryError),
      `treated as authored: ${JSON.stringify(odd)}`,
    );
  }
});
