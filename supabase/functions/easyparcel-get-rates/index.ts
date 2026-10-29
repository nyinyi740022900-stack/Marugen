// All available courier prices in SGD; the paid service remains authoritative.
import { courierEligibilityError } from "../_shared/delivery.ts";
import {
  authenticated,
  corsHeaders,
  DeliveryError,
  failure,
  json,
  loadOrder,
} from "../_shared/delivery_api.ts";
import { fetchRates, paidFx } from "../_shared/shipping_api.ts";
import {
  bookingParcel,
  bookingQuoteError,
} from "../_shared/shipping_finance.ts";
import { validateParcel } from "../_shared/delivery.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { admin } = await authenticated(req);
    const { order_id, parcel: requested } = await req.json();
    const order = await loadOrder(admin, order_id);
    const reason = courierEligibilityError(order);
    if (reason) throw new DeliveryError(reason, 409);
    const accepted = !!order.shipping_quote_id && !!order.shipping_parcel;
    const parcel = accepted
      ? bookingParcel(order.shipping_parcel, requested)
      : validateParcel(requested);
    const rates = await fetchRates(
      admin,
      order.shipping_address,
      parcel,
      accepted ? paidFx(order) : undefined,
      accepted,
    );
    return json({
      rates: rates.map((rate) => {
        const message = accepted
          ? bookingQuoteError(order, rate.service_id, parcel, rate)
          : "No prepaid delivery quote. Arrange seller-paid booking in EasyParcel.";
        return {
          ...rate,
          booking_available: !message,
          booking_message: message,
        };
      }),
      parcel,
    });
  } catch (error) {
    return failure(error);
  }
});
