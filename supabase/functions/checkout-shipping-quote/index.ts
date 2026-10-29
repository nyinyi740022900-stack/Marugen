import {
  authenticated,
  corsHeaders,
  DeliveryError,
  failure,
  json,
} from "../_shared/delivery_api.ts";
import {
  checkoutBinding,
  fetchRates,
  officialFx,
} from "../_shared/shipping_api.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { admin, user } = await authenticated(req, false);
    const { items, shipping_address, promo_code, all_couriers } = await req
      .json();
    const binding = await checkoutBinding(
      admin,
      items,
      shipping_address,
      promo_code,
    );
    const available = binding.fulfillment === "courier"
      ? (await fetchRates(
        admin,
        shipping_address,
        binding.parcel!,
        officialFx,
        false,
        all_couriers === true ? "all" : "legacy_tracx",
      ))
      : [];
    // Address-only checkout cannot promise a locker/collection-point service.
    // The owner can still compare every service in the SGD quotation list.
    const rate = available.find((r) =>
      all_couriers !== true || r.door_to_door
    ) ?? null;
    if (binding.fulfillment === "courier" && !rate) {
      throw new DeliveryError(
        "No pickup and home-delivery service is available for this parcel",
        502,
      );
    }
    const quote = {
      user_id: user.id,
      checkout_signature: binding.checkout_signature,
      pricing_signature: binding.pricing_signature,
      expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      currency: "SGD",
      fulfillment_method: binding.fulfillment,
      shipping_cost_policy: binding.fulfillment === "shop_delivery"
        ? "seller_100"
        : "shared_50_50",
      carrier_name: rate?.carrier_name ?? null,
      service_id: rate?.service_id ?? null,
      total_shipping_cents: rate?.total_shipping_cents ?? 0,
      buyer_shipping_cents: rate?.buyer_shipping_cents ?? 0,
      seller_shipping_cents: rate?.seller_shipping_cents ?? 0,
      source_currency: rate?.source_currency ?? null,
      source_shipping_amount: rate?.source_shipping_amount ?? null,
      fx_rate: rate?.fx_rate ?? null,
      fx_date: rate?.fx_date ?? null,
      fx_source: rate?.fx_source ?? null,
      parcel: binding.parcel,
    };
    const { data, error } = await admin.from("shipping_quotes").insert(quote)
      .select("id").single();
    if (error || !data) {
      throw error ?? new DeliveryError("Could not save delivery quote", 500);
    }
    const {
      user_id: _user,
      checkout_signature: _checkout,
      pricing_signature: _pricing,
      ...publicQuote
    } = quote;
    return json({ quote_id: data.id, ...publicQuote });
  } catch (error) {
    return failure(error);
  }
});
