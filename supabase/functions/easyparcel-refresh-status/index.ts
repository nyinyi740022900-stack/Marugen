import {
  loadParcels,
  refreshOrderParcels,
} from "../_shared/order_parcels_api.ts";
// Customer/admin on-demand pull through EasyParcel's existing tracking API.
import {
  applyEasyparcelTracking,
  authenticated,
  corsHeaders,
  DeliveryError,
  failure,
  fetchEasyparcelTracking,
  json,
  loadOrder,
  requireAdmin,
} from "../_shared/delivery_api.ts";
import { EasyParcelNotConnectedError } from "../_shared/easyparcel_token.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { admin, user } = await authenticated(req, false);
    const { order_id } = await req.json();
    const order = await loadOrder(admin, order_id);
    if (order.user_id !== user.id) await requireAdmin(admin, user.id);
    if ((await loadParcels(admin, order.id)).length) {
      return json({ parcels: await refreshOrderParcels(admin, order.id) });
    }
    if (order.tracking_provider !== "easyparcel") {
      throw new DeliveryError("This order is not tracked via EasyParcel");
    }
    if (!order.qxpress_tracking_no) {
      throw new DeliveryError(
        "This booking needs attention. Ask the shop to reconcile the existing EasyParcel shipment.",
        409,
      );
    }
    const tracking = await fetchEasyparcelTracking(
      admin,
      order.qxpress_tracking_no,
    );
    const saved = await applyEasyparcelTracking(admin, order, tracking);
    return json({ status: saved.status, detail: saved.detail });
  } catch (error) {
    if (error instanceof EasyParcelNotConnectedError) {
      return json({ error: error.message }, 409);
    }
    return failure(error);
  }
});
