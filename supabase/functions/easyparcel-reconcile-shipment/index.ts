// Reconcile a confirmed EXISTING shipment, never release/rebook a claim.
// EasyParcel has no verified shipment-id -> AWB recovery API in this app;
// staff obtain the AWB from its dashboard and attest it belongs to this order.
import { recoveryError } from "../_shared/delivery.ts";
import {
  applyEasyparcelTracking,
  authenticated,
  corsHeaders,
  DeliveryError,
  failure,
  fetchEasyparcelTracking,
  json,
  loadOrder,
} from "../_shared/delivery_api.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { admin } = await authenticated(req);
    const { order_id, tracking_number, confirmed_existing_shipment } = await req
      .json();
    let order = await loadOrder(admin, order_id);
    const number = typeof tracking_number === "string"
      ? tracking_number.trim()
      : tracking_number;
    const reason = recoveryError(order, number, confirmed_existing_shipment);
    if (reason) throw new DeliveryError(reason, 409);
    const tracking = await fetchEasyparcelTracking(admin, number);
    if (
      order.easyparcel_shipment_id && tracking.shipmentId &&
      order.easyparcel_shipment_id !== tracking.shipmentId
    ) {
      throw new DeliveryError(
        "Tracking number belongs to a different EasyParcel shipment",
        409,
      );
    }
    // Re-read after the network call so a finished in-flight booking or
    // terminal lifecycle update cannot be overwritten by reconciliation.
    order = await loadOrder(admin, order_id);
    if (
      order.easyparcel_shipment_id && tracking.shipmentId &&
      order.easyparcel_shipment_id !== tracking.shipmentId
    ) {
      throw new DeliveryError(
        "Tracking number belongs to a different EasyParcel shipment",
        409,
      );
    }
    const changed = recoveryError(order, number, confirmed_existing_shipment);
    if (changed) throw new DeliveryError(changed, 409);
    let update = admin.from("orders").update({
      qxpress_tracking_no: number,
      easyparcel_booking_state: "booked",
      tracking_status: "Booked",
      tracking_status_code: 7,
      tracking_updated_at: new Date().toISOString(),
    })
      .eq("id", order.id).eq("status", order.status).eq(
        "tracking_provider",
        "easyparcel",
      ).eq("tracking_registered", true).eq(
        "easyparcel_booking_state",
        order.easyparcel_booking_state,
      );
    update = order.qxpress_tracking_no
      ? update.eq("qxpress_tracking_no", order.qxpress_tracking_no)
      : update.is("qxpress_tracking_no", null);
    update = order.easyparcel_booking_started_at
      ? update.eq(
        "easyparcel_booking_started_at",
        order.easyparcel_booking_started_at,
      )
      : update.is("easyparcel_booking_started_at", null);
    const { data, error } = await update.select("id").maybeSingle();
    if (error || !data) {
      throw error ??
        new DeliveryError(
          "Booking changed during reconciliation; refresh and try again",
          409,
        );
    }
    await applyEasyparcelTracking(admin, {
      ...order,
      qxpress_tracking_no: number,
    }, tracking);
    return json({ ok: true, tracking_number: number, status: tracking.text });
  } catch (error) {
    return failure(error);
  }
});
