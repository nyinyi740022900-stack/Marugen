import {
  BookingRejectedError,
  isSampleTracking,
} from "./pickup_diagnostics.ts";
export class DeliveryValidationError extends Error {}
export type DeliveryOrder = {
  status: string;
  fulfillment_method?: string;
  tracking_registered?: boolean;
  tracking_provider?: string | null;
  items?: Array<{ product_category?: unknown; product_id?: unknown }>;
  qxpress_tracking_no?: string | null;
  easyparcel_booking_state?: string | null;
  easyparcel_booking_started_at?: string | null;
};
export type Parcel = {
  weight_kg: number;
  length_cm: number;
  width_cm: number;
  height_cm: number;
  collection_date: string;
};
export type Shipment = {
  trackingNumber: string | null;
  shipmentId: string | null;
  awbUrl: string | null;
};
export function classifyFulfillment(
  items: DeliveryOrder["items"],
): "shop_delivery" | "courier" | "review_required" {
  if (
    items?.some((i) =>
      i.product_category === "koi" || i.product_category === "arowana"
    )
  ) return "shop_delivery";
  if (
    !items?.length ||
    items.some((i) =>
      !["fish_food", "accessories"].includes(String(i.product_category))
    )
  ) return "review_required";
  return "courier";
}
export function courierEligibilityError(order: DeliveryOrder): string | null {
  if (!["paid", "packing"].includes(order.status)) {
    return "Only paid or packing orders can use courier delivery";
  }
  if (
    order.fulfillment_method !== "courier" ||
    classifyFulfillment(order.items) !== "courier"
  ) return "This order requires shop delivery or a fulfillment review";
  if (
    order.tracking_registered || order.tracking_provider ||
    order.qxpress_tracking_no
  ) return "This order already has a shipment or booking claim";
  return null;
}
// EasyParcel OpenAPI shipment codes: 3 Collected, 4 Delivery In Transit,
// 5 Delivered, 11 Drop Off. 6 Returned / 7 Scheduled / 8 Hold are NOT proof
// of collection. Unknown future codes must not advance the order lifecycle.
export function easyparcelOrderStatus(
  current: string,
  code: unknown,
): string | null {
  if (code === 5 && ["paid", "packing", "shipped"].includes(current)) {
    return "delivered";
  }
  if (
    [3, 4, 11].includes(code as number) && ["paid", "packing"].includes(current)
  ) return "shipped";
  return null;
}
export function validateParcel(input: unknown, now = new Date()): Parcel {
  if (!input || typeof input !== "object") {
    throw new DeliveryValidationError(
      "Enter the parcel weight, dimensions and collection date",
    );
  }
  const p = input as Record<string, unknown>;
  for (const k of ["weight_kg", "length_cm", "width_cm", "height_cm"]) {
    if (
      typeof p[k] !== "number" || !Number.isFinite(p[k]) ||
      (p[k] as number) <= 0
    ) {
      throw new DeliveryValidationError(
        "Parcel weight and dimensions must be positive numbers",
      );
    }
  }
  const date = p.collection_date;
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Singapore",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
  if (
    typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
    !Number.isFinite(Date.parse(date)) ||
    new Date(date).toISOString().slice(0, 10) !== date || date <= today
  ) {
    throw new DeliveryValidationError(
      "Choose a collection date after today in Singapore",
    );
  }
  return {
    weight_kg: p.weight_kg as number,
    length_cm: p.length_cm as number,
    width_cm: p.width_cm as number,
    height_cm: p.height_cm as number,
    collection_date: date,
  };
}
export function validateSingaporeAddress(
  input: unknown,
): {
  recipient_name: string;
  phone: string;
  line1: string;
  line2: string;
  postal_code: string;
  city: string;
} {
  if (!input || typeof input !== "object") {
    throw new DeliveryValidationError(
      "A complete Singapore delivery address is required",
    );
  }
  const a = input as Record<string, unknown>;
  const str = (key: string) =>
    typeof a[key] === "string" ? (a[key] as string).trim() : "";
  const phone = str("phone").replace(/[\s()-]/g, "").replace(/^\+65/, "");
  if (
    !str("recipient_name") || !str("line1") || !/^[3689]\d{7}$/.test(phone) ||
    !/^\d{6}$/.test(str("postal_code")) ||
    (a.country && !["SG", "Singapore"].includes(String(a.country)))
  ) {
    throw new DeliveryValidationError(
      "Enter a name, Singapore phone, street address and six-digit postal code",
    );
  }
  return {
    recipient_name: str("recipient_name"),
    phone,
    line1: str("line1"),
    line2: str("line2"),
    postal_code: str("postal_code"),
    city: str("city") || "Singapore",
  };
}
export function recoveryError(
  order: DeliveryOrder,
  number: unknown,
  confirmed: unknown,
  now = new Date(),
): string | null {
  if (
    confirmed !== true || typeof number !== "string" ||
    !/^[A-Za-z0-9-]{3,100}$/.test(number)
  ) return "Confirm the existing EasyParcel tracking number before reconciling";
  if (
    !["paid", "packing", "shipped"].includes(order.status) ||
    order.fulfillment_method !== "courier" ||
    classifyFulfillment(order.items) !== "courier"
  ) return "This order is not eligible for courier reconciliation";
  if (!order.tracking_registered || order.tracking_provider !== "easyparcel") {
    return "An existing EasyParcel booking claim is required";
  }
  if (order.qxpress_tracking_no && order.qxpress_tracking_no !== number) {
    return "Cannot replace an existing tracking number";
  }
  if (order.easyparcel_booking_state !== "needs_attention") {
    const started = Date.parse(order.easyparcel_booking_started_at ?? "");
    if (
      order.easyparcel_booking_state !== "booking" ||
      !Number.isFinite(started) || now.getTime() - started < 15 * 60 * 1000
    ) return "Booking is still in progress; refresh before reconciling";
  }
  return null;
}
export async function runBooking(
  port: {
    claim: () => Promise<boolean>;
    submit: () => Promise<Shipment>;
    persist: (shipment: Shipment) => Promise<void>;
    attention: (shipment?: Shipment, issue?: string | null) => Promise<void>;
  },
): Promise<{ ok: boolean; needsAttention?: boolean; shipment?: Shipment }> {
  if (!await port.claim()) return { ok: false };
  let shipment: Shipment | undefined;
  try {
    shipment = await port.submit();
    await port.persist(shipment);
    if (
      !shipment.trackingNumber || isSampleTracking(shipment.trackingNumber) ||
      isSampleTracking(shipment.shipmentId)
    ) {
      return { ok: false, needsAttention: true, shipment };
    }
    return { ok: true, shipment };
  } catch (error) {
    console.error("[delivery] booking requires reconciliation", error);
    try {
      await port.attention(
        shipment,
        error instanceof BookingRejectedError ? error.issue : null,
      );
    } catch (writeError) {
      console.error(
        "[delivery] could not persist attention state; claim retained",
        writeError,
      );
    }
    return { ok: false, needsAttention: true, shipment };
  }
}
export function manualRegistrationError(
  order: DeliveryOrder,
  confirmed: unknown,
  number?: unknown,
): string | null {
  if (confirmed !== true) {
    return "Confirm that the parcel has physically been handed to the courier";
  }
  if (!["paid", "packing", "shipped"].includes(order.status)) {
    return "Only paid, packing or shipped orders can register a handover";
  }
  const retry = order.tracking_provider === "seventeentrack" &&
    order.tracking_registered && typeof number === "string" &&
    order.qxpress_tracking_no === number;
  return courierEligibilityError({
    ...order,
    status: "paid",
    ...(retry
      ? {
        tracking_provider: null,
        tracking_registered: false,
        qxpress_tracking_no: null,
      }
      : {}),
  });
}
export function seventeentrackOrderStatus(
  current: string,
  status: unknown,
): string | null {
  return current === "shipped" && typeof status === "string" &&
      status.toLowerCase() === "delivered"
    ? "delivered"
    : null;
}
export function manualCarrier(
  requested: unknown,
  saved: unknown,
): number | null {
  const value = requested ?? saved ?? null;
  if (value == null) return null;
  if (!Number.isInteger(value) || Number(value) <= 0) {
    throw new DeliveryValidationError(
      "Carrier code must be a positive integer",
    );
  }
  if (saved != null && requested != null && requested !== saved) {
    throw new DeliveryValidationError(
      "Carrier differs from the saved shipment",
    );
  }
  return Number(value);
}
