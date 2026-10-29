import {
  authenticated,
  corsHeaders,
  DeliveryError,
  failure,
  json,
  loadOrder,
} from "../_shared/delivery_api.ts";
import {
  EasyParcelNotConnectedError,
  getEasyParcelAccessToken,
} from "../_shared/easyparcel_token.ts";
import { checkPickup } from "../_shared/pickup_diagnostics.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { admin } = await authenticated(req); // owner/staff only; no customer wallet access
    const { order_id } = await req.json();
    const order = await loadOrder(admin, order_id);
    if (
      order.fulfillment_method !== "courier" ||
      order.tracking_provider !== "easyparcel"
    ) {
      throw new DeliveryError(
        "This order does not have an EasyParcel courier booking",
        409,
      );
    }
    const token = await getEasyParcelAccessToken(admin);
    return json(await checkPickup(token, order));
  } catch (error) {
    if (error instanceof EasyParcelNotConnectedError) {
      return json({
        error:
          "Reconnect EasyParcel using your live account, then check pickup again.",
      }, 409);
    }
    if (error instanceof DeliveryError) return failure(error);
    return json({
      error:
        "Could not check EasyParcel. Reconnect the live account and try again.",
    }, 502);
  }
});
