import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkoutBinding, fetchRates } from "./shipping_api.ts";
function assert(value: unknown) {
  if (!value) throw new Error("Assertion failed");
}
const settings = {
  gst_percent: 9,
  gst_included_in_price: true,
  shop_name: "Test shop",
  shop_phone: "81234567",
  shop_address: "1 Test Street",
  shop_postcode: "718788",
  shop_city: "Singapore",
  shop_country: "SG",
};
const address = {
  recipient_name: "Buyer",
  phone: "81234567",
  line1: "2 Test Street",
  postal_code: "059893",
  city: "Singapore",
  country: "SG",
};
function client(
  category = "fish_food",
  weight: number | null = 0.5,
  dimensions: unknown = null,
) {
  const rows: Record<string, unknown> = {
    products: [{ id: "p", category, price: 10, shipping_weight_kg: 3 }],
    product_variants: [{
      id: "v",
      product_id: "p",
      price: 10,
      shipping_weight_kg: weight,
      packed_dimensions: dimensions,
    }],
    settings,
    easyparcel_connection: {
      access_token: "test-only",
      access_token_expires_at: new Date(Date.now() + 3600000).toISOString(),
    },
  };
  return {
    from(table: string) {
      const result = { data: rows[table], error: null };
      const query = {
        select: () => query,
        in: () => Promise.resolve(result),
        eq: () => query,
        single: () => Promise.resolve(result),
        maybeSingle: () => Promise.resolve(result),
      };
      return query;
    },
  } as unknown as SupabaseClient;
}
Deno.test("shipping adapter sends selected SKU kg × qty; all courier rates normalize to SGD", async () => {
  const admin = client();
  const binding = await checkoutBinding(
    admin,
    [{ product_id: "p", variant_id: "v", quantity: 3 }],
    address,
    null,
  );
  assert(binding.parcel?.weight_kg === 1.5);
  assert(binding.parcel?.length_cm === undefined);
  const original = globalThis.fetch;
  let called = 0;
  globalThis.fetch = async (input, init) => {
    assert(
      String(input) ===
        "https://api.easyparcel.com/open_api/2026-06/shipment/quotations",
    );
    const payload = JSON.parse(String(init?.body));
    assert(payload.shipment[0].weight === 1.5);
    assert(!("length" in payload.shipment[0]));
    assert(payload.auto_apply_coupon === false);
    called++;
    return Response.json({
      status_code: 200,
      data: [{
        quotations: [
          {
            courier: { courier_name: "Other", service_id: "X" },
            pricing: { currency: "SGD", total_amount: 1 },
          },
          {
            courier: { courier_name: "TracX Logis", service_id: "T" },
            pricing: { currency: "MYR", total_amount: 13.49 },
          },
        ],
      }],
    });
  };
  try {
    const rates = await fetchRates(
      admin,
      address,
      binding.parcel!,
      async () => ({
        rate: 0.31329,
        date: new Date().toISOString().slice(0, 10),
        source: "test ECB snapshot",
      }),
    );
    assert(called === 1 && rates.length === 2 && rates[1].service_id === "T");
    const legacy = await fetchRates(
      admin,
      address,
      binding.parcel!,
      async () => ({
        rate: 0.31329,
        date: new Date().toISOString().slice(0, 10),
        source: "test",
      }),
      false,
      "legacy_tracx",
    );
    assert(legacy.length === 1 && legacy[0].service_id === "T");
    assert(
      rates[1].currency === "SGD" && rates[1].total_shipping_cents === 423,
    );
    assert(
      rates[1].buyer_shipping_cents === 211 &&
        rates[1].seller_shipping_cents === 212,
    );
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("live fish routing bypasses missing weights; changed SKU kg invalidates pricing signature", async () => {
  const items = [{ product_id: "p", variant_id: "v", quantity: 3 }];
  const shop = await checkoutBinding(client("koi", null), items, address, null);
  assert(shop.fulfillment === "shop_delivery" && shop.parcel === null);
  const a = await checkoutBinding(client(), items, address, null);
  const b = await checkoutBinding(client("fish_food", 1), items, address, null);
  assert(
    a.checkout_signature === b.checkout_signature &&
      a.pricing_signature !== b.pricing_signature,
  );
  let rejected = false;
  try {
    await checkoutBinding(client("fish_food", null), items, address, null);
  } catch {
    rejected = true;
  }
  assert(rejected);
});

Deno.test("single packed SKU dimensions quote its box; multiple units do not invent a combined box", async () => {
  const admin = client("fish_food", 0.5, {
    length_cm: 20,
    width_cm: 10,
    height_cm: 8,
  });
  const one = await checkoutBinding(
    admin,
    [{ product_id: "p", variant_id: "v", quantity: 1 }],
    address,
    null,
  );
  assert(
    one.parcel?.length_cm === 20 && one.parcel?.width_cm === 10 &&
      one.parcel?.height_cm === 8,
  );
  const many = await checkoutBinding(
    admin,
    [{ product_id: "p", variant_id: "v", quantity: 2 }],
    address,
    null,
  );
  assert(many.parcel?.weight_kg === 1 && many.parcel?.length_cm === undefined);
});
