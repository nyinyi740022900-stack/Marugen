import {
  DeliveryValidationError,
  type Parcel,
  type Shipment,
  validateParcel,
} from "./delivery.ts";
import { isSampleTracking } from "./pickup_diagnostics.ts";
export type Allocation = { order_item_id: string; quantity: number };
export type PlannedParcel = Parcel & { items: Allocation[] };
export function validateAllocation(
  lines: { id: string; quantity: number }[],
  input: unknown,
): PlannedParcel[] {
  if (!Array.isArray(input) || input.length < 2 || input.length > 20) {
    throw new DeliveryValidationError(
      "Split delivery requires 2 to 20 actual boxes",
    );
  }
  const totals = new Map(lines.map((i) => [i.id, 0]));
  const result = input.map((value) => {
    const parcel = validateParcel(value);
    const items = value.items;
    if (!Array.isArray(items) || !items.length) {
      throw new DeliveryValidationError("Each box needs ordered items");
    }
    const seen = new Set<string>();
    for (const item of items) {
      if (
        !totals.has(item.order_item_id) || seen.has(item.order_item_id) ||
        !Number.isSafeInteger(item.quantity) || item.quantity < 1
      ) {
        throw new DeliveryValidationError(
          "Invalid, duplicate or foreign order item allocation",
        );
      }
      seen.add(item.order_item_id);
      totals.set(
        item.order_item_id,
        totals.get(item.order_item_id)! + item.quantity,
      );
    }
    return {
      ...parcel,
      items: items.map((i: Allocation) => ({
        order_item_id: i.order_item_id,
        quantity: i.quantity,
      })),
    };
  });
  if (lines.some((i) => totals.get(i.id) !== i.quantity)) {
    throw new DeliveryValidationError(
      "Allocate every ordered unit exactly once across boxes",
    );
  }
  return result;
}
export function cheapestPickupRate<
  T extends {
    door_to_door: boolean;
    pickup_minimum?: number;
    total_shipping_cents: number;
    service_id: string;
  },
>(rates: T[]): T {
  const allowed = rates.filter((r) =>
    r.door_to_door && r.pickup_minimum !== undefined && r.pickup_minimum <= 1
  ).sort((a, b) =>
    a.total_shipping_cents - b.total_shipping_cents ||
    a.service_id.localeCompare(b.service_id)
  );
  if (!allowed.length) {
    throw new DeliveryValidationError(
      "No eligible single-parcel door pickup rate is available",
    );
  }
  return allowed[0];
}
export type BookingOutcome = {
  state: string;
  tracking_number: string | null;
  shipment_number: string | null;
  awb_url: string | null;
  diagnostic_code: string | null;
};
export async function runParcelBookings<T extends { id: string }>(
  parcels: T[],
  port: {
    claim: () => Promise<boolean>;
    submit: (p: T) => Promise<Shipment & { paymentRequired?: boolean }>;
    persist: (p: T, outcome: BookingOutcome) => Promise<void>;
  },
) {
  if (!await port.claim()) {
    throw new DeliveryValidationError(
      "Plan changed or already claimed. Refresh the quote and approve again",
    );
  }
  let stopped = false;
  for (const p of parcels) {
    let outcome: BookingOutcome = {
      state: "needs_attention",
      tracking_number: null,
      shipment_number: null,
      awb_url: null,
      diagnostic_code: stopped
        ? "not_attempted_after_failure"
        : "submission_uncertain",
    };
    if (!stopped) {
      try {
        const s = await port.submit(p);
        const sample = isSampleTracking(s.trackingNumber) ||
          isSampleTracking(s.shipmentId);
        const safe = !sample && !s.paymentRequired && !!s.trackingNumber &&
          !!s.shipmentId;
        outcome = {
          state: s.paymentRequired
            ? "payment_required"
            : safe
            ? "booked"
            : "needs_attention",
          tracking_number: sample ? null : s.trackingNumber,
          shipment_number: sample ? null : s.shipmentId,
          awb_url: safe && s.awbUrl?.startsWith("https://") ? s.awbUrl : null,
          diagnostic_code: sample
            ? "sample_tracking"
            : s.paymentRequired
            ? "payment_required"
            : safe
            ? null
            : "missing_tracking",
        };
        if (!safe) stopped = true;
      } catch {
        stopped = true;
      }
    }
    // Persistence failure is fatal: all rows were already claimed; never resubmit.
    await port.persist(p, outcome);
  }
}
export function parcelTrackingState(
  code: number | null,
  text: string | null,
): string {
  if (
    ["waiting payment", "expired (unpaid)"].includes(
      (text ?? "").trim().toLowerCase(),
    )
  ) return "payment_required";
  return ({
    0: "cancelled",
    3: "collected",
    4: "in_transit",
    5: "delivered",
    6: "returned",
    8: "on_hold",
    11: "collected",
  } as Record<number, string>)[code ?? -1] ?? "booked";
}
export function assertParcelApproval(
  parcels: {
    quote_signature: string | null;
    quote_expires_at: string | null;
  }[],
  signature: string,
  total: number,
  approved: unknown,
  approvedSignature: unknown,
  now = Date.now(),
): void {
  if (
    approvedSignature !== signature || !Number.isSafeInteger(approved) ||
    approved !== total ||
    parcels.some((p) =>
      p.quote_signature !== signature || !p.quote_expires_at ||
      !Number.isFinite(Date.parse(p.quote_expires_at)) ||
      Date.parse(p.quote_expires_at) <= now
    )
  ) {
    throw new DeliveryValidationError(
      "The quote changed or expired. Refresh it and explicitly approve the new total before booking",
    );
  }
}
export function assertParcelTrackingIdentity(
  parcel: { tracking_number: string | null; shipment_number: string | null },
  tracking: { returnedNumber: string | null; shipmentId: string | null },
) {
  if (
    !parcel.tracking_number || !parcel.shipment_number ||
    tracking.returnedNumber !== parcel.tracking_number ||
    tracking.shipmentId !== parcel.shipment_number
  ) {
    throw new DeliveryValidationError(
      "Provider tracking identity does not match the parcel",
    );
  }
}
export function parcelRecoveryDetails(
  parcel: { shipment_number: string | null; tracking_number: string | null },
  data: unknown,
): { number: string; awbUrl: string | null } | null {
  if (
    !parcel.shipment_number || isSampleTracking(parcel.shipment_number) ||
    !Array.isArray(data)
  ) return null;
  const row = data.find((r) => r?.shipment_number === parcel.shipment_number);
  const d = row?.shipment_details;
  if (
    !d || typeof d.awb_number !== "string" || !d.awb_number.trim() ||
    isSampleTracking(d.awb_number) ||
    (parcel.tracking_number && parcel.tracking_number !== d.awb_number)
  ) return null;
  return {
    number: d.awb_number,
    awbUrl: typeof d.awb_url === "string" && d.awb_url.startsWith("https://")
      ? d.awb_url
      : null,
  };
}
export function parcelPackingHints(
  item: {
    variant_id: string | null;
    variant?:
      | { shipping_weight_kg: unknown; packed_dimensions: unknown }
      | null;
    product?:
      | { shipping_weight_kg: unknown; packed_dimensions: unknown }
      | null;
  },
) {
  const sku = item.variant_id ? item.variant : item.product;
  return {
    weight_kg: sku?.shipping_weight_kg ?? null,
    packed_dimensions: sku?.packed_dimensions ?? null,
  };
}
