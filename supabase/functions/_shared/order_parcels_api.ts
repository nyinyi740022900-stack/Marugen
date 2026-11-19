import {
  assertParcelTrackingIdentity,
  parcelRecoveryDetails,
} from "./order_parcels.ts";
import { DeliveryValidationError } from "./delivery.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  DeliveryError,
  fetchEasyparcelShipmentDetails,
  fetchEasyparcelTracking,
  rpcError,
} from "./delivery_api.ts";
export async function loadParcels(admin: SupabaseClient, orderId: string) {
  const { data, error } = await admin.from("order_parcels").select("*").eq(
    "order_id",
    orderId,
  ).order("parcel_number");
  if (error) throw error;
  return data ?? [];
}
export async function refreshOrderParcels(
  admin: SupabaseClient,
  orderId: string,
  parcelId?: string,
) {
  const parcels = await loadParcels(admin, orderId);
  if (parcelId && !parcels.some((p) => p.id === parcelId)) {
    throw new DeliveryError("Parcel not found", 404);
  }
  for (const parcel of parcels.filter((p) => !parcelId || p.id === parcelId)) {
    if (
      !parcel.shipment_number || ["draft", "booking"].includes(parcel.state)
    ) continue;
    let number = parcel.tracking_number;
    let recovered: { number: string; awbUrl: string | null } | null = null;
    if (!number || !parcel.awb_url || parcel.state === "payment_required") {
      recovered = parcelRecoveryDetails(
        parcel,
        await fetchEasyparcelShipmentDetails(admin, parcel.shipment_number),
      );
      if (recovered) number = recovered.number;
    }
    if (!number) continue;
    const tracking = await fetchEasyparcelTracking(
      admin,
      number,
    );
    // Absence is not proof: require BOTH exact authenticated provider identities.
    try {
      assertParcelTrackingIdentity(
        { ...parcel, tracking_number: number },
        tracking,
      );
    } catch (error) {
      // Same authored refusal, as a conflict rather than a bad request.
      throw error instanceof DeliveryValidationError
        ? new DeliveryError(error.message, 409)
        : error;
    }
    if (recovered) {
      const { error } = await admin.rpc("recover_order_parcel_identity", {
        p_parcel_id: parcel.id,
        p_shipment: parcel.shipment_number,
        p_awb: recovered.number,
        p_awb_url: recovered.awbUrl,
      });
      if (error) throw rpcError(error);
    }
    const { error } = await admin.rpc("apply_order_parcel_tracking", {
      p_parcel_id: parcel.id,
      p_awb: tracking.number,
      p_shipment: tracking.shipmentId,
      p_code: tracking.code,
      p_text: tracking.text,
      p_observed_at: tracking.observedAt,
      p_event_at: tracking.eventAt,
    });
    if (error) throw rpcError(error);
  }
  return await loadParcels(admin, orderId);
}
