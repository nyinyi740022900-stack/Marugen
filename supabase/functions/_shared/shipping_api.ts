import { type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { DeliveryError, loadSender } from "./delivery_api.ts";
import { classifyFulfillment, validateSingaporeAddress } from "./delivery.ts";
import { getEasyParcelAccessToken } from "./easyparcel_token.ts";
import {
  canonicalCheckout,
  cartWeightKg,
  type Fx,
  isTracX,
  normalizeRates,
  type QuoteParcel,
  signature,
  trustedParcel,
} from "./shipping_finance.ts";
export async function officialFx(): Promise<Fx> {
  const response = await fetch(
    "https://api.frankfurter.dev/v2/providers/ecb/rate/MYR/SGD",
    { signal: AbortSignal.timeout(10000) },
  );
  if (!response.ok) {
    throw new DeliveryError(
      "MYR to SGD exchange rate unavailable; try again later",
      502,
    );
  }
  const data = await response.json();
  if (
    String(data.base).toUpperCase() !== "MYR" ||
    String(data.quote).toUpperCase() !== "SGD"
  ) throw new DeliveryError("Invalid exchange rate response", 502);
  return {
    rate: Number(data.rate),
    date: String(data.date),
    source: "Frankfurter/ECB",
  };
}
export async function checkoutBinding(
  admin: SupabaseClient,
  items: unknown,
  address: unknown,
  promo: unknown,
) {
  const canonical = canonicalCheckout(items, address, promo);
  const normalized = JSON.parse(canonical);
  const ids = [
    ...new Set(
      normalized.items.map((i: { product_id: string }) => i.product_id),
    ),
  ];
  const { data: products, error } = await admin.from("products").select(
    "id,category,price,sale_price,show_price,size_options,shipping_weight_kg,packed_dimensions",
  ).in("id", ids);
  if (error) throw error;
  if (products?.length !== ids.length) {
    throw new DeliveryError("Product not found");
  }
  const variantIds = normalized.items.map((i: { variant_id: string | null }) =>
    i.variant_id
  ).filter(Boolean);
  let variants: Record<string, unknown>[] = [];
  if (variantIds.length) {
    const { data, error } = await admin.from("product_variants").select(
      "id,product_id,price,shipping_weight_kg,packed_dimensions",
    ).in("id", variantIds);
    if (error) throw error;
    variants = data ?? [];
  }
  const { data: settings, error: settingsError } = await admin.from("settings")
    .select(
      "gst_percent,gst_included_in_price,default_parcel_weight_kg,default_parcel_length_cm,default_parcel_width_cm,default_parcel_height_cm,shop_name,shop_phone,shop_address,shop_postcode,shop_city,shop_state,shop_country",
    ).eq("id", 1).single();
  if (settingsError) throw settingsError;
  let promotion: unknown = null;
  if (normalized.promo) {
    // Same exact lookup as create-payment-intent; never ILIKE wildcards.
    const { data, error } = await admin.rpc("find_promo_code", {
      p_code: normalized.promo,
    }).select(
      "id,code,discount_type,discount_value,active,expires_at,max_redemptions",
    );
    if (error) throw error;
    promotion = (Array.isArray(data) ? data[0] : data) ?? null;
  }
  const ordered = (rows: unknown[]) =>
    rows.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  const pricing = JSON.stringify({
    products: ordered(products),
    variants: ordered(variants),
    settings,
    promotion,
  });
  const fulfillment = classifyFulfillment(
    products.map((p) => ({ product_category: p.category })),
  );
  if (fulfillment === "review_required") {
    throw new DeliveryError(
      "This cart needs a delivery review before checkout",
    );
  }
  // A unit's packed box describes exactly one unit. Never sum dimensions
  // across a cart or multiply them by quantity to invent a packed parcel.
  const only =
    normalized.items.length === 1 && normalized.items[0].quantity === 1
      ? normalized.items[0]
      : null;
  const sku = only?.variant_id
    ? variants.find((v) =>
      v.id === only.variant_id && v.product_id === only.product_id
    )
    : products.find((p) => p.id === only?.product_id);
  const packed = sku?.packed_dimensions;
  const parcelSettings = packed && typeof packed === "object"
    ? {
      ...settings,
      ...Object.fromEntries(
        ["length_cm", "width_cm", "height_cm"].map((
          key,
        ) => [
          "default_parcel_" + key,
          (packed as Record<string, unknown>)[key],
        ]),
      ),
    }
    : settings;
  return {
    checkout_signature: await signature(canonical),
    pricing_signature: await signature(pricing),
    fulfillment,
    settings,
    parcel: fulfillment === "courier"
      ? trustedParcel(
        cartWeightKg(normalized.items, products, variants),
        parcelSettings,
      )
      : null,
  };
}
export async function fetchRates(
  admin: SupabaseClient,
  address: unknown,
  parcel: QuoteParcel,
  fx: () => Promise<Fx> = officialFx,
  acceptedSnapshot = false,
  carrierPolicy: "all" | "legacy_tracx" = "all",
) {
  const shipping = validateSingaporeAddress(address);
  const sender = await loadSender(admin);
  const token = await getEasyParcelAccessToken(admin);
  const response = await fetch(
    "https://api.easyparcel.com/open_api/2026-06/shipment/quotations",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(20000),
      body: JSON.stringify({
        shipment: [{
          sender: {
            postcode: sender.postcode,
            subdivision_code: sender.subdivision_code,
            country: "SG",
          },
          receiver: {
            postcode: shipping.postal_code,
            subdivision_code: "",
            country: "SG",
          },
          weight: parcel.weight_kg,
          length: parcel.length_cm,
          width: parcel.width_cm,
          height: parcel.height_cm,
          collection_date: parcel.collection_date,
        }],
        auto_apply_coupon: false,
      }),
    },
  );
  const body = await response.json();
  if (!response.ok || (body.status_code && body.status_code !== 200)) {
    throw new DeliveryError(
      "EasyParcel rates unavailable; try again later",
      502,
    );
  }
  const result = body?.data?.[0];
  if (
    !result || result.status === "error" || !Array.isArray(result.quotations)
  ) {
    throw new DeliveryError(
      "No courier service available for this parcel",
      502,
    );
  }
  const rates = await normalizeRates(result.quotations, fx, new Date(), {
    acceptedSnapshot,
  });
  const allowed = carrierPolicy === "all"
    ? rates
    : rates.filter((r) => isTracX(r.carrier_name));
  if (!allowed.length) {
    throw new DeliveryError(
      "No courier service available for this parcel",
      502,
    );
  }
  return allowed;
}
export function orderShippingFields(
  q: Record<string, unknown> | null,
  checkoutSignature: string,
  fulfillment: string,
) {
  return {
    shipping_quote_id: q?.id ?? null,
    shipping_currency: "SGD",
    total_shipping_cents: q?.total_shipping_cents ?? 0,
    buyer_shipping_cents: q?.buyer_shipping_cents ?? 0,
    seller_shipping_cents: q?.seller_shipping_cents ?? 0,
    shipping_carrier_name: q?.carrier_name ?? null,
    shipping_service_id: q?.service_id ?? null,
    shipping_parcel: q?.parcel ?? null,
    shipping_source_currency: q?.source_currency ?? null,
    shipping_source_amount: q?.source_shipping_amount ?? null,
    shipping_fx_rate: q?.fx_rate ?? null,
    shipping_fx_date: q?.fx_date ?? null,
    shipping_fx_source: q?.fx_source ?? null,
    shipping_cost_policy: fulfillment === "shop_delivery"
      ? "seller_100"
      : "shared_50_50",
    shipping_checkout_signature: checkoutSignature,
  };
}

// Preserve the buyer's accepted SGD conversion when a paid MYR booking is
// rechecked. The source courier amount must still match before any booking.
export function paidFx(order: Record<string, unknown>): () => Promise<Fx> {
  return order.shipping_source_currency === "MYR"
    ? async () => ({
      rate: Number(order.shipping_fx_rate),
      date: String(order.shipping_fx_date),
      source: String(order.shipping_fx_source),
    })
    : officialFx;
}
