// EasyParcel webhook.
//
// SOURCE-IP DIAGNOSTIC (temporary, added to settle the allowlist question
// below). Every request logs one line:
//
//   [easyparcel-webhook] source-ip {"allowed":true,"decision_ip":"47.254.255.46",
//     "decision_from":"x-forwarded-for[0]",
//     "x_forwarded_for":["47.254.255.46","172.70.1.9"],
//     "headers":{"x-real-ip":["172.70.1.9"],"cf-connecting-ip":["47.254.255.46"]},
//     "other_header_names":[],
//     "allowlisted_at":[{"header":"x-forwarded-for","index":0,"from_end":2,"ip":"47.254.255.46"}, ...]}
//
// It holds IP addresses and header names only: never the body, the
// Authorization header or any other header value.
//
// How to read it, using ONE delivery that is known to be genuine (trigger a
// status change in EasyParcel and match the log line by time):
//   * `x_forwarded_for` is left to right; index 0 is what the caller (or its
//     own proxy) wrote, later entries were appended by the hops in front of
//     this function. `from_end` counts from the right (1 = last entry).
//   * `allowlisted_at` shows where EasyParcel's address really arrives. The
//     trustworthy position is one the platform writes itself: a fixed
//     `from_end` in x-forwarded-for, or a single-value header such as
//     cf-connecting-ip / x-real-ip.
//   * To confirm that position cannot be chosen by the caller, send one test
//     request from another machine with a made-up header
//     (curl -H 'x-forwarded-for: 47.254.255.46' ...): it is answered 403 or
//     200 exactly as today, and its log line shows whether the made-up value
//     landed at index 0 only (then index 0 is forgeable, as suspected) and
//     which header/position held the machine's real address instead.
//
// What to change afterwards, in the handler below:
//   * replace the `ip` expression with the position the genuine delivery
//     proved, e.g. the entry `from_end` N of x-forwarded-for
//     (`chain[chain.length - N]`) or `req.headers.get("cf-connecting-ip")`;
//   * if EasyParcel's address never appears at a platform-written position,
//     the allowlist cannot be made reliable: drop it and rely only on the
//     authenticated re-read (already the only thing that changes state);
//   * then delete this diagnostic, its import and _shared/source_ip.ts.
import { refreshOrderParcels } from "../_shared/order_parcels_api.ts";
import { parcelRecoveryDetails } from "../_shared/order_parcels.ts";
// EasyParcel has no signed webhook (per existing integration support notes).
// Retain source allowlist, treat payloads as hints, then verify status with
// authenticated tracking_status API before changing the order lifecycle.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { ipOnly, sourceIpDiagnostic } from "../_shared/source_ip.ts";
import {
  applyEasyparcelTracking,
  fetchEasyparcelShipmentDetails,
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
    // KNOWN LIMIT, deliberately unchanged in Sprint 3: this reads the FIRST
    // x-forwarded-for entry. Proxies append the address they saw to whatever
    // the caller sent, so the first entry is the one a caller can choose and
    // this allowlist can be passed by sending the header. Which entry is the
    // real peer depends on how many hops the platform adds in front of the
    // function, which cannot be observed from the repository; picking the
    // wrong one would reject every genuine webhook. It is therefore left as
    // is and treated as a noise filter only: nothing below trusts the
    // payload, every state change comes from an authenticated EasyParcel
    // read matched on the stored shipment number and AWB.
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      req.headers.get("x-real-ip");
    const allowed = !!ip && ALLOWED_SOURCE_IPS.has(ip);
    // Diagnostic only (see the file header); it never changes `allowed`.
    try {
      console.log(
        "[easyparcel-webhook] source-ip",
        JSON.stringify({
          allowed,
          // The entry the allowlist was applied to.
          decision_ip: ip ? ipOnly(ip) : null,
          decision_from: req.headers.get("x-forwarded-for") !== null
            ? "x-forwarded-for[0]"
            : "x-real-ip",
          ...sourceIpDiagnostic(req.headers, ALLOWED_SOURCE_IPS),
        }),
      );
    } catch (diagnosticError) {
      console.error(
        "[easyparcel-webhook] source-ip diagnostic failed",
        diagnosticError,
      );
    }
    if (!allowed) {
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
      // The label link staff open and print is never taken from this
      // unsigned payload (a forged request could point it anywhere). The
      // topic is only a hint to re-read the shipment from EasyParcel with our
      // own token; the link is stored only when that answer carries this
      // order's shipment number AND its AWB.
      if (
        body.topic === "shipment.awb.update" && order.easyparcel_shipment_id
      ) {
        let verified: { awbUrl: string | null } | null = null;
        try {
          verified = parcelRecoveryDetails(
            {
              shipment_number: order.easyparcel_shipment_id,
              tracking_number: awb,
            },
            await fetchEasyparcelShipmentDetails(
              admin,
              order.easyparcel_shipment_id,
            ),
          );
        } catch (detailsError) {
          // A label link that could not be read must not hold up tracking.
          console.error(
            "[easyparcel-webhook] label link not verified",
            order.id,
            detailsError,
          );
        }
        if (verified?.awbUrl) {
          const { error: awbError } = await admin.from("orders").update({
            easyparcel_awb_url: verified.awbUrl,
          }).eq("id", order.id).eq("tracking_provider", "easyparcel").eq(
            "qxpress_tracking_no",
            awb,
          );
          if (awbError) throw awbError;
        }
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
