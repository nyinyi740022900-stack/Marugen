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
import {
  EasyParcelNotConnectedError,
  EasyParcelRefreshError,
  getEasyParcelAccessToken,
} from "./easyparcel_token.ts";
import { fetchWithTimeout, TIMEOUT_MS } from "./http.ts";
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
/**
 * A delivery failure whose message was written for the person using the app
 * (staff, or the customer at checkout-shipping-quote). Only this class and
 * the other authored classes listed in deliveryFailure() reach the response.
 * Never build one from a caught error's message, a database error or a
 * provider body: use rpcError() for RPC failures and fixed copy otherwise.
 */
export class DeliveryError extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}
export const DELIVERY_FAILED_MESSAGE =
  "Delivery request failed. Refresh and try again; if it keeps failing, contact support.";
/**
 * What the caller may be told about a failure. Authored messages pass with
 * their status; anything else (database errors, provider and network
 * errors, bugs) becomes fixed copy with status 500 and is left to the logs.
 */
export function deliveryFailure(
  error: unknown,
): { message: string; status: number; authored: boolean } {
  if (error instanceof DeliveryError) {
    return { message: error.message, status: error.status, authored: true };
  }
  if (error instanceof DeliveryValidationError) {
    return { message: error.message, status: 400, authored: true };
  }
  if (error instanceof EasyParcelNotConnectedError) {
    return { message: error.message, status: 409, authored: true };
  }
  if (error instanceof EasyParcelRefreshError) {
    return { message: error.message, status: 503, authored: true };
  }
  return { message: DELIVERY_FAILED_MESSAGE, status: 500, authored: false };
}
/**
 * Error to throw for a failed RPC. A plain `raise exception` in our own
 * functions (SQLSTATE P0001) is a business rule written for staff, e.g.
 * "Fresh quote and exact owner approval required", and is passed on. Every
 * other database error (constraint names, casts, permissions, timeouts) is
 * returned untouched so the handler replaces it with fixed copy.
 */
export function rpcError(
  error: { code?: string; message?: string },
  status = 409,
): unknown {
  return error?.code === "P0001" && typeof error.message === "string" &&
      error.message
    ? new DeliveryError(error.message, status)
    : error;
}
export function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
export function failure(error: unknown, tag = "[delivery]") {
  const { message, status, authored } = deliveryFailure(error);
  // Authored refusals are expected and carry no detail worth a stack trace.
  if (authored) console.error(tag, status, message);
  else console.error(tag, "unexpected failure", error);
  return json({ error: message }, status);
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
  if (error) throw rpcError(error);
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
      new DeliveryError(
        "Booking metadata could not be saved; reconcile the existing shipment",
        502,
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
  let response: Response;
  let body;
  try {
    response = await fetchWithTimeout(
      "https://api.easyparcel.com/open_api/2026-06/shipment/tracking_status",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ awb_numbers: [number] }),
      },
      TIMEOUT_MS.provider,
    );
    body = await response.json();
  } catch (error) {
    // Timeout, dropped connection or a non-JSON body: nothing was verified.
    console.error("[delivery] tracking_status did not complete", error);
    throw new DeliveryError(
      "EasyParcel tracking could not be verified; try again later",
      502,
    );
  }
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
// Authenticated read of one shipment from EasyParcel. Returns the provider's
// `data` array, or null when EasyParcel answered but refused the request.
// Callers must still match the shipment number (and AWB) inside it before
// trusting any field.
export async function fetchEasyparcelShipmentDetails(
  admin: SupabaseClient,
  shipmentNumber: string,
): Promise<unknown> {
  const token = await getEasyParcelAccessToken(admin);
  let response: Response;
  let body;
  try {
    response = await fetchWithTimeout(
      "https://api.easyparcel.com/open_api/2026-09/shipment/details",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ shipment_number: shipmentNumber }),
      },
      TIMEOUT_MS.provider,
    );
    body = await response.json();
  } catch (error) {
    console.error("[delivery] shipment details did not complete", error);
    throw new DeliveryError(
      "EasyParcel shipment details could not be read; try again later",
      502,
    );
  }
  return response.ok && body.status_code === 200 ? body.data : null;
}
export async function notifyOrder(
  orderId: string,
  payload: { status?: string; event?: string },
) {
  try {
    const res = await fetchWithTimeout(
      `${supabaseUrl}/functions/v1/send-order-notification`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ order_id: orderId, ...payload }),
      },
      TIMEOUT_MS.notify,
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
  if (error) throw rpcError(error);
  if (data?.status_changed) {
    await notifyOrder(order.id, { status: data.order_status });
  }
  if (data?.applied && tracking.code === 6) {
    await notifyOrder(order.id, { event: "shipment_returned" });
  }
  return data;
}
