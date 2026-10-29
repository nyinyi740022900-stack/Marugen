import {
  bookingFailureCode,
  BookingRejectedError,
} from "../_shared/pickup_diagnostics.ts";
// Booking reserves a label. Only verified carrier collection advances shipped.
import {
  bookingParcel,
  bookingQuoteError,
} from "../_shared/shipping_finance.ts";
import { fetchRates, paidFx } from "../_shared/shipping_api.ts";
import {
  courierEligibilityError,
  runBooking,
  validateParcel,
  validateSingaporeAddress,
} from "../_shared/delivery.ts";
import {
  authenticated,
  claimShipment,
  corsHeaders,
  DeliveryError,
  failure,
  json,
  loadOrder,
  loadSender,
  saveBooking,
} from "../_shared/delivery_api.ts";
import {
  EasyParcelNotConnectedError,
  getEasyParcelAccessToken,
} from "../_shared/easyparcel_token.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { admin } = await authenticated(req);
    const { order_id, service_id, parcel: input } = await req.json();
    if (!service_id || !["string", "number"].includes(typeof service_id)) {
      throw new DeliveryError("service_id is required");
    }
    const requestedParcel = input ? validateParcel(input) : null;
    const order = await loadOrder(admin, order_id);
    const eligibility = courierEligibilityError(order);
    if (eligibility) throw new DeliveryError(eligibility, 409);
    if (!order.shipping_parcel) {
      throw new DeliveryError(
        "Legacy order has no paid quote. Arrange seller-paid delivery outside this booking flow",
        409,
      );
    }
    const parcel = bookingParcel(order.shipping_parcel, requestedParcel);
    const rates = await fetchRates(
      admin,
      order.shipping_address,
      parcel,
      paidFx(order),
      true,
    );
    const rate = rates.find((r) => r.service_id === String(service_id));
    const quoteError = bookingQuoteError(
      order,
      service_id,
      requestedParcel ?? parcel,
      rate,
    );
    if (quoteError) throw new DeliveryError(quoteError, 409);
    const shipping = validateSingaporeAddress(order.shipping_address);
    const sender = await loadSender(admin);
    const token = await getEasyParcelAccessToken(admin);
    const result = await runBooking({
      claim: () => claimShipment(admin, order.id, "easyparcel"),
      submit: async () => {
        const dimensions = {
          weight: parcel.weight_kg,
          length: parcel.length_cm,
          width: parcel.width_cm,
          height: parcel.height_cm,
        };
        const response = await fetch(
          "https://api.easyparcel.com/open_api/2026-06/shipment/submit_orders",
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${token}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              shipment: [{
                reference: order.id,
                auto_apply_coupon: false,
                service_id,
                collection_date: parcel.collection_date,
                ...dimensions,
                item: [{
                  content: (order.items ?? []).map((
                    i: Record<string, unknown>,
                  ) =>
                    `${
                      [i.product_name, i.variant_label, i.size_label].filter(
                        Boolean,
                      ).join(" / ")
                    } x${i.quantity}`
                  ).join("; "),
                  ...dimensions,
                  currency_code: "SGD",
                  value: order.total,
                  quantity: 1,
                }],
                sender,
                receiver: {
                  name: shipping.recipient_name,
                  phone_number_country_code: "SG",
                  phone_number: shipping.phone,
                  address_1: shipping.line1,
                  address_2: shipping.line2,
                  postcode: shipping.postal_code,
                  city: shipping.city,
                  subdivision_code: "",
                  country_code: "SG",
                },
              }],
            }),
          },
        );
        const body = await response.json();
        const shipment = body?.data?.[0]?.shipments?.[0];
        if (
          !response.ok || (body.status_code && body.status_code !== 200) ||
          shipment?.status !== "success"
        ) {
          throw new BookingRejectedError(bookingFailureCode(body));
        }
        // A shipment number is not an AWB: never substitute it for tracking.
        return {
          trackingNumber: shipment.awb_number || null,
          shipmentId: shipment.shipment_number || null,
          awbUrl: shipment.awb_url || null,
        };
      },
      persist: (shipment) => saveBooking(admin, order.id, shipment),
      attention: (shipment, issue) =>
        saveBooking(
          admin,
          order.id,
          shipment ?? { trackingNumber: null, shipmentId: null, awbUrl: null },
          true,
          issue,
        ),
    });
    if (!result.ok) {
      return json({
        error: result.needsAttention
          ? "Booking needs attention. Check EasyParcel and reconcile this existing shipment; do not book another shipment."
          : "Order is no longer eligible or already has a booking claim.",
        needs_attention: result.needsAttention ?? false,
        shipment_id: result.shipment?.shipmentId ?? null,
      }, result.needsAttention ? 502 : 409);
    }
    return json({
      ok: true,
      tracking_number: result.shipment?.trackingNumber,
      awb_url: result.shipment?.awbUrl ?? null,
    });
  } catch (error) {
    if (error instanceof EasyParcelNotConnectedError) {
      return json({ error: error.message }, 409);
    }
    return failure(error);
  }
});
