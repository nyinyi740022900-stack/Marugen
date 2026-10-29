import { parseTrackingEvidence } from "./tracking_evidence.ts";
import { isSampleTracking } from "./pickup_diagnostics.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import {
  DeliveryValidationError,
  type Shipment,
  validateSingaporeAddress,
} from "./delivery.ts";
import { getEasyParcelAccessToken } from "./easyparcel_token.ts";
export const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
export const serviceRoleKey = Deno.env.get("SB_SERVICE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const anonKey = Deno.env.get("SB_ANON_KEY") ??
  Deno.env.get("SUPABASE_ANON_KEY") ?? "";
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
export class DeliveryError extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}
export function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
export function failure(error: unknown) {
  console.error("[delivery]", error);
  return json(
    {
      error: error instanceof Error ? error.message : "Delivery request failed",
    },
    error instanceof DeliveryError
      ? error.status
      : error instanceof DeliveryValidationError
      ? 400
      : 500,
  );
}
export async function authenticated(req: Request, adminOnly = true) {
  if (req.method !== "POST") throw new DeliveryError("POST required", 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    throw new DeliveryError("Missing Authorization header", 401);
  }
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) throw new DeliveryError("Unauthorized", 401);
  const admin = createClient(supabaseUrl, serviceRoleKey);
  if (adminOnly) await requireAdmin(admin, user.id);
  return { admin, user };
}
export async function requireAdmin(admin: SupabaseClient, userId: string) {
  const { data, error } = await admin.from("profiles").select("role").eq(
    "id",
    userId,
  ).maybeSingle();
  if (error) throw error;
  if (!data || !["staff", "owner"].includes(data.role)) {
    throw new DeliveryError("Admin access required", 403);
  }
}
export async function loadOrder(admin: SupabaseClient, id: unknown) {
  if (typeof id !== "string" || !id) {
    throw new DeliveryError("order_id is required");
  }
  const { data, error } = await admin.from("orders").select(
    "*,items:order_items(*)",
  ).eq("id", id).maybeSingle();
  if (error) throw error;
  if (!data) throw new DeliveryError("Order not found", 404);
  return data;
}
export async function loadSender(admin: SupabaseClient) {
  const { data, error } = await admin.from("settings").select(
    "shop_name,shop_phone,shop_address,shop_postcode,shop_city,shop_state,shop_country",
  ).eq("id", 1).maybeSingle();
  if (error) throw error;
  if (!data) throw new DeliveryError("Shop address settings are missing");
  const normalized = validateSingaporeAddress({
    recipient_name: data.shop_name,
    phone: data.shop_phone,
    line1: data.shop_address,
    postal_code: data.shop_postcode,
    city: data.shop_city,
    country: data.shop_country,
  });
  return {
    name: normalized.recipient_name,
    phone_number_country_code: "SG",
    phone_number: normalized.phone,
    address_1: normalized.line1,
    postcode: normalized.postal_code,
    city: normalized.city,
    subdivision_code: data.shop_state ?? "",
    country_code: "SG",
  };
}
export async function claimShipment(
  admin: SupabaseClient,
  id: string,
  provider: string,
  number: string | null = null,
  carrier: number | null = null,
) {
  const { data, error } = await admin.rpc("claim_courier_shipment", {
    p_order_id: id,
    p_provider: provider,
    p_tracking_number: number,
    p_carrier_code: carrier,
  });
  if (error) throw error;
  return data === true;
}
export async function saveBooking(
  admin: SupabaseClient,
  id: string,
  shipment: Shipment,
  attention = false,
  issue: string | null = null,
) {
  attention = attention || isSampleTracking(shipment.trackingNumber) ||
    isSampleTracking(shipment.shipmentId);
  const { data, error } = await admin.from("orders").update({
    ...(shipment.trackingNumber
      ? { qxpress_tracking_no: shipment.trackingNumber }
      : {}),
    ...(shipment.shipmentId
      ? { easyparcel_shipment_id: shipment.shipmentId }
      : {}),
    ...(shipment.awbUrl ? { easyparcel_awb_url: shipment.awbUrl } : {}),
    easyparcel_booking_state: attention || !shipment.trackingNumber
      ? "needs_attention"
      : "booked",
    tracking_status: attention || !shipment.trackingNumber
      ? "Needs attention"
      : "Booked",
    ...(issue && ["insufficient_credit", "invalid_details"].includes(issue)
      ? { tracking_status_detail: `booking_issue:${issue}` }
      : {}),
    tracking_status_code: 7,
    tracking_updated_at: new Date().toISOString(),
  }).eq("id", id).eq("tracking_provider", "easyparcel").eq(
    "tracking_registered",
    true,
  ).is("qxpress_tracking_no", null).select("id").maybeSingle();
  if (error || !data) {
    throw error ??
      new Error(
        "Booking metadata could not be saved; reconcile the existing shipment",
      );
  }
}
export type TrackingResult = {
  number: string;
  returnedNumber: string | null;
  shipmentId: string | null;
  code: number | null;
  text: string | null;
  location: string | null;
  observedAt: string;
  eventAt: string | null;
};
export async function fetchEasyparcelTracking(
  admin: SupabaseClient,
  number: string,
): Promise<TrackingResult> {
  if (isSampleTracking(number)) {
    throw new DeliveryError(
      "Sample tracking is not a live pickup confirmation. Reconnect using the live EasyParcel account and check the existing booking.",
      409,
    );
  }
  const observedAt = new Date().toISOString();
  const token = await getEasyParcelAccessToken(admin);
  const response = await fetch(
    "https://api.easyparcel.com/open_api/2026-06/shipment/tracking_status",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ awb_numbers: [number] }),
    },
  );
  const body = await response.json();
  if (!response.ok || (body.status_code && body.status_code !== 200)) {
    throw new DeliveryError(
      "EasyParcel tracking could not be verified; try again later",
      502,
    );
  }
  try {
    return { ...parseTrackingEvidence(body?.data, number), observedAt };
  } catch {
    throw new DeliveryError(
      "EasyParcel has no verified tracking matching this number yet",
      502,
    );
  }
}
export async function notifyOrder(
  orderId: string,
  payload: { status?: string; event?: string },
) {
  try {
    const res = await fetch(
      `${supabaseUrl}/functions/v1/send-order-notification`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ order_id: orderId, ...payload }),
      },
    );
    if (!res.ok) console.error("[delivery] notification failed", res.status);
  } catch (error) {
    console.error("[delivery] notification failed", error);
  }
}
export async function applyEasyparcelTracking(
  admin: SupabaseClient,
  order: { id: string; status: string; qxpress_tracking_no?: string | null },
  tracking: TrackingResult,
) {
  const { data, error } = await admin.rpc("apply_easyparcel_order_tracking", {
    p_order_id: order.id,
    p_awb: tracking.number,
    p_shipment: tracking.shipmentId,
    p_code: tracking.code,
    p_text: tracking.text,
    p_detail: tracking.location,
    p_observed_at: tracking.observedAt,
    p_event_at: tracking.eventAt,
  });
  if (error) throw error;
  if (data?.status_changed) {
    await notifyOrder(order.id, { status: data.order_status });
  }
  if (data?.applied && tracking.code === 6) {
    await notifyOrder(order.id, { event: "shipment_returned" });
  }
  return data;
}
