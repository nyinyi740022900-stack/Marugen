// Admin attests physical handover before manual 17TRACK registration.
import { manualCarrier, manualRegistrationError } from "../_shared/delivery.ts";
import {
  authenticated,
  claimShipment,
  corsHeaders,
  DeliveryError,
  failure,
  json,
  loadOrder,
  notifyOrder,
} from "../_shared/delivery_api.ts";
import { fetchWithTimeout, TIMEOUT_MS } from "../_shared/http.ts";
const track17ApiKey = Deno.env.get("TRACK17_API_KEY") ?? "";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { admin } = await authenticated(req);
    const { order_id, tracking_number, carrier_code, confirmed_handover } =
      await req.json();
    if (
      typeof tracking_number !== "string" ||
      !/^[A-Za-z0-9-]{3,100}$/.test(tracking_number.trim())
    ) throw new DeliveryError("Enter a valid courier tracking number");
    const number = tracking_number.trim();
    if (
      carrier_code != null &&
      (!Number.isInteger(carrier_code) || carrier_code <= 0)
    ) throw new DeliveryError("Carrier code must be a positive integer");
    const order = await loadOrder(admin, order_id);
    const carrier = manualCarrier(carrier_code, order.tracking_carrier_code);
    const reason = manualRegistrationError(order, confirmed_handover, number);
    if (reason) throw new DeliveryError(reason, 409);
    const retry = order.tracking_provider === "seventeentrack" &&
      order.qxpress_tracking_no === number;
    if (
      !retry &&
      !await claimShipment(
        admin,
        order.id,
        "seventeentrack",
        number,
        carrier,
      )
    ) {
      throw new DeliveryError(
        "Order changed or another booking claimed it. Refresh first.",
        409,
      );
    }
    // Claim + candidate AWB + confirmed shipped handover are one database
    // mutation, so a concurrent packing update cannot strand a blank claim.
    if (!retry && order.status !== "shipped") {
      await notifyOrder(order.id, { status: "shipped" });
    }
    let response: Response;
    let body;
    try {
      response = await fetchWithTimeout(
        "https://api.17track.net/track/v2.4/register",
        {
          method: "POST",
          headers: {
            "17token": track17ApiKey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify([{
            number,
            ...(carrier ? { carrier } : {}),
          }]),
        },
        TIMEOUT_MS.provider,
      );
      body = await response.json();
    } catch (error) {
      // The handover is already saved. Registering the same number again is
      // safe (17TRACK answers "already registered"), so staff can retry.
      console.error("[track-register] 17TRACK did not respond", error);
      throw new DeliveryError(
        "Handover saved, but 17TRACK registration needs attention. Do not book another shipment.",
        502,
      );
    }
    const accepted = body?.data?.accepted?.[0],
      rejected = body?.data?.rejected?.[0];
    if (
      !response.ok ||
      (!accepted &&
        !String(rejected?.error?.message ?? "").toLowerCase().includes(
          "already",
        ))
    ) {
      throw new DeliveryError(
        "Handover saved, but 17TRACK registration needs attention. Do not book another shipment.",
        502,
      );
    }
    const { data, error } = await admin.from("orders").update({
      tracking_carrier_code: carrier,
      tracking_status: "Registered",
      tracking_updated_at: new Date().toISOString(),
    })
      .eq("id", order.id).eq("tracking_provider", "seventeentrack").eq(
        "qxpress_tracking_no",
        number,
      ).in("status", ["paid", "packing", "shipped"]).select("id").maybeSingle();
    if (error || !data) {
      throw error ??
        new Error("Tracking registration metadata could not be saved");
    }
    return json({
      ok: true,
      carrier,
    });
  } catch (error) {
    return failure(error);
  }
});
