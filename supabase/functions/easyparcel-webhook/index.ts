import { refreshOrderParcels } from "../_shared/order_parcels_api.ts";
// EasyParcel has no signed webhook (per existing integration support notes).
// Retain source allowlist, treat payloads as hints, then verify status with
// authenticated tracking_status API before changing the order lifecycle.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  applyEasyparcelTracking,
  fetchEasyparcelTracking,
  notifyOrder,
  serviceRoleKey,
  supabaseUrl,
} from "../_shared/delivery_api.ts";
const admin = createClient(supabaseUrl, serviceRoleKey);
const ALLOWED_SOURCE_IPS = new Set(["47.254.255.46", "117.53.155.92"]);
function reply(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
Deno.serve(async (req) => {
  try {
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      req.headers.get("x-real-ip");
    if (!ip || !ALLOWED_SOURCE_IPS.has(ip)) {
      return reply({ received: false, error: "untrusted source" }, 403);
    }
    const body = await req.json();
    const shipmentId = typeof body.shipment_number === "string"
      ? body.shipment_number
      : null;
    const number = typeof body.awb_number === "string" ? body.awb_number : null;
    if (!shipmentId && !number) return reply({ received: true });
    // Multi-parcel payloads are hints only. Resolve an existing parcel, then
    // pull authenticated provider evidence matching BOTH stored identities.
    let parcelQuery = admin.from("order_parcels").select(
      "id,order_id,tracking_number,shipment_number",
    );
    parcelQuery = shipmentId
      ? parcelQuery.eq("shipment_number", shipmentId)
      : parcelQuery.eq("tracking_number", number);
    const { data: matchingParcels, error: parcelError } = await parcelQuery;
    if (parcelError) throw parcelError;
    for (const parcel of matchingParcels ?? []) {
      if (
        number && parcel.tracking_number && number !== parcel.tracking_number
      ) continue;
      if (shipmentId && shipmentId !== parcel.shipment_number) continue;
      await refreshOrderParcels(admin, parcel.order_id, parcel.id);
    }
    let query = admin.from("orders").select(
      "id,status,qxpress_tracking_no,easyparcel_shipment_id",
    ).eq("tracking_provider", "easyparcel").eq("tracking_registered", true);
    query = shipmentId
      ? query.eq("easyparcel_shipment_id", shipmentId)
      : query.eq("qxpress_tracking_no", number);
    const { data: orders, error } = await query;
    if (error) throw error;
    for (const order of orders ?? []) {
      const awb = order.qxpress_tracking_no ?? number;
      if (!awb) continue;
      // Stored AWB owns the shipment; a webhook must not replace it.
      if (
        number && order.qxpress_tracking_no &&
        number !== order.qxpress_tracking_no
      ) continue;
      const tracking = await fetchEasyparcelTracking(admin, awb);
      if (
        tracking.shipmentId && order.easyparcel_shipment_id &&
        tracking.shipmentId !== order.easyparcel_shipment_id
      ) continue;
      if (!order.qxpress_tracking_no) {
        const { data: saved, error: saveError } = await admin.from("orders")
          .update({
            qxpress_tracking_no: awb,
            easyparcel_booking_state: "booked",
          })
          .eq("id", order.id).eq("tracking_provider", "easyparcel").eq(
            "easyparcel_shipment_id",
            shipmentId,
          ).is("qxpress_tracking_no", null).select("id").maybeSingle();
        if (saveError) throw saveError;
        if (!saved) continue;
      }
      if (
        body.topic === "shipment.awb.update" &&
        typeof body.awb_url === "string" && body.awb_url.startsWith("https://")
      ) {
        const { error: awbError } = await admin.from("orders").update({
          easyparcel_awb_url: body.awb_url,
        }).eq("id", order.id).eq("tracking_provider", "easyparcel").eq(
          "qxpress_tracking_no",
          awb,
        );
        if (awbError) throw awbError;
      }
      const saved = await applyEasyparcelTracking(admin, {
        ...order,
        qxpress_tracking_no: awb,
      }, tracking);
      if (
        saved.applied &&
        tracking.text?.toLowerCase().includes("out for delivery") &&
        ["paid", "packing", "shipped"].includes(order.status)
      ) await notifyOrder(order.id, { event: "out_for_delivery" });
    }
    return reply({ received: true });
  } catch (error) {
    console.error(
      "[easyparcel-webhook] verification/persistence failed",
      error,
    );
    return reply({
      received: false,
      error: "Tracking could not be verified or saved; retry later",
    }, 503);
  }
});
