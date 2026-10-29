import {
  DeliveryValidationError,
  type Parcel,
  validateParcel,
  validateSingaporeAddress,
} from "./delivery.ts";
export const CARRIER_NAME = "TracX Logis";
export function isTracX(name: unknown): boolean {
  return typeof name === "string" &&
    [
      "tracx logis",
      "tracx logis pte ltd",
      "tracx logis pte. ltd",
      "track x",
      "trac x",
    ].includes(
      name.trim().toLowerCase(),
    );
}
export type Fx = { rate: number; date: string; source: string };
export type Rate = {
  service_id: string;
  courier_id: string;
  carrier_name: string;
  courier_name: string;
  door_to_door: boolean;
  pickup_minimum?: number;
  currency: "SGD";
  price: number;
  total_shipping_cents: number;
  buyer_shipping_cents: number;
  seller_shipping_cents: number;
  source_currency: string;
  source_shipping_amount: number;
  fx_rate: number;
  fx_date: string;
  fx_source: string;
};
export async function normalizeRates(
  quotations: unknown[],
  fx: () => Promise<Fx>,
  now = new Date(),
  options: { acceptedSnapshot?: boolean } = {},
): Promise<Rate[]> {
  let exchange: Fx | undefined;
  const rates: Rate[] = [];
  for (const value of quotations) {
    const q = value as {
      courier?: {
        courier_name?: unknown;
        service_id?: unknown;
        courier_id?: unknown;
        service_tag?: unknown;
      };
      pricing?: { currency?: unknown; total_amount?: unknown };
    };
    const name = q.courier?.courier_name;
    if (typeof name !== "string" || !name.trim() || name.trim().length > 200) {
      continue;
    }
    // Keep accepted historical TracX snapshots compatible with its legal name.
    const carrier = isTracX(name) ? CARRIER_NAME : name.trim();
    const tags = Array.isArray(q.courier?.service_tag)
      ? q.courier.service_tag
      : [];
    const method = (value: string) =>
      tags.some((tag) =>
        tag?.name === "Service Methods" && tag?.value === value
      );
    const service = q.courier?.service_id;
    if (!["string", "number"].includes(typeof service) || !String(service)) {
      continue;
    }
    const currency = String(q.pricing?.currency ?? "").toUpperCase();
    const amount = Number(q.pricing?.total_amount);
    if (
      q.pricing?.total_amount == null || !Number.isFinite(amount) || amount <= 0
    ) {
      throw new DeliveryValidationError(
        "Courier returned an invalid shipping total",
      );
    }
    if (!["SGD", "MYR"].includes(currency)) {
      throw new DeliveryValidationError(
        "Unsupported shipping quote currency; only SGD or verified MYR conversion is supported",
      );
    }
    if (currency === "MYR") {
      exchange ??= await fx();
      const date = Date.parse(exchange.date + "T00:00:00Z");
      if (
        !/^\d{4}-\d{2}-\d{2}$/.test(exchange.date) || !Number.isFinite(date) ||
        date > now.getTime() ||
        (!options.acceptedSnapshot && now.getTime() - date > 5 * 86400000) ||
        !Number.isFinite(exchange.rate) || exchange.rate <= 0
      ) {
        throw new DeliveryValidationError(
          "A fresh MYR to SGD exchange rate is unavailable; try again later",
        );
      }
    }
    const rate = currency === "SGD" ? 1 : exchange!.rate;
    const total = Math.round(amount * rate * 100);
    if (!Number.isSafeInteger(total) || total <= 0) {
      throw new DeliveryValidationError("Invalid SGD shipping total");
    }
    const buyer = Math.floor(total / 2);
    rates.push({
      service_id: String(service),
      courier_id: String(q.courier?.courier_id ?? ""),
      carrier_name: carrier,
      courier_name: carrier,
      door_to_door: method("Pick Up from Door") && method("Deliver to Door"),
      // Explicit provider bulk-pickup restrictions must survive normalization.
      pickup_minimum: (() => {
        const moq = tags.find((tag) => tag?.name === "Pick Up MOQ");
        if (!moq) return 1;
        const count = Number(moq.value);
        return Number.isSafeInteger(count) && count > 0 ? count : Infinity;
      })(),
      currency: "SGD",
      price: total / 100,
      total_shipping_cents: total,
      buyer_shipping_cents: buyer,
      seller_shipping_cents: total - buyer,
      source_currency: currency,
      source_shipping_amount: amount,
      fx_rate: rate,
      fx_date: currency === "SGD"
        ? now.toISOString().slice(0, 10)
        : exchange!.date,
      fx_source: currency === "SGD"
        ? "EasyParcel native SGD"
        : exchange!.source,
    });
  }
  return rates.sort((a, b) =>
    a.total_shipping_cents - b.total_shipping_cents ||
    a.service_id.localeCompare(b.service_id)
  );
}
export function canonicalCheckout(
  items: unknown,
  address: unknown,
  promo: unknown,
): string {
  if (!Array.isArray(items) || !items.length || items.length > 100) {
    throw new DeliveryValidationError(
      "Cart must contain between 1 and 100 lines",
    );
  }
  const normalized = items.map((v) => {
    const i = v as Record<string, unknown>;
    if (
      typeof i.product_id !== "string" || !i.product_id ||
      !Number.isInteger(i.quantity) || Number(i.quantity) < 1 ||
      Number(i.quantity) > 10000
    ) throw new DeliveryValidationError("Invalid cart line");
    for (const key of ["variant_id", "size_label"]) {
      if (i[key] != null && typeof i[key] !== "string") {
        throw new DeliveryValidationError("Invalid cart option");
      }
    }
    return {
      product_id: i.product_id,
      quantity: Number(i.quantity),
      variant_id: i.variant_id || null,
      size_label: typeof i.size_label === "string"
        ? i.size_label.trim() || null
        : null,
    };
  }).sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  if (promo != null && typeof promo !== "string") {
    throw new DeliveryValidationError("Invalid promo code");
  }
  return JSON.stringify({
    items: normalized,
    address: validateSingaporeAddress(address),
    promo: typeof promo === "string" ? promo.trim().toUpperCase() : "",
  });
}
export async function signature(value: string): Promise<string> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
export function requireQuote(
  q: Record<string, unknown> | null,
  user: string,
  checkout: string,
  pricing: string,
  now = new Date(),
) {
  if (
    !q || q.user_id !== user || q.checkout_signature !== checkout ||
    q.pricing_signature !== pricing ||
    !Number.isFinite(Date.parse(String(q.expires_at))) ||
    Date.parse(String(q.expires_at)) <= now.getTime()
  ) {
    throw new DeliveryValidationError(
      "Shipping quote expired or checkout changed. Refresh delivery pricing before payment",
    );
  }
}
export type QuoteParcel =
  & Pick<Parcel, "weight_kg" | "collection_date">
  & Partial<Pick<Parcel, "length_cm" | "width_cm" | "height_cm">>;
export function cartWeightKg(
  items: Array<
    { product_id: string; quantity: number; variant_id?: string | null }
  >,
  products: Array<Record<string, unknown>>,
  variants: Array<Record<string, unknown>>,
): number {
  let total = 0;
  for (const item of items) {
    const product = products.find((p) => p.id === item.product_id);
    const sku = item.variant_id
      ? variants.find((v) =>
        v.id === item.variant_id && v.product_id === item.product_id
      )
      : product;
    const weight = Number(sku?.shipping_weight_kg);
    if (
      !sku || !Number.isFinite(weight) || weight <= 0 ||
      !Number.isInteger(item.quantity) || item.quantity <= 0
    ) {
      throw new DeliveryValidationError(
        "Set the shipping weight in kg for each selected product option before courier checkout",
      );
    }
    total += weight * item.quantity;
  }
  total = Math.round(total * 1000000) / 1000000;
  if (!Number.isFinite(total) || total <= 0) {
    throw new DeliveryValidationError("Invalid total shipping weight");
  }
  return total;
}
export function trustedParcel(
  weight: number,
  s: Record<string, unknown>,
  now = new Date(),
): QuoteParcel {
  if (!Number.isFinite(weight) || weight <= 0) {
    throw new DeliveryValidationError("Invalid total shipping weight");
  }
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Singapore",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
  const tomorrow = new Date(today + "T00:00:00Z");
  tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
  const parcel: QuoteParcel = {
    weight_kg: weight,
    collection_date: tomorrow.toISOString().slice(0, 10),
  };
  const dimensions = ["length_cm", "width_cm", "height_cm"] as const;
  if (dimensions.some((k) => s["default_parcel_" + k] != null)) {
    const full = validateParcel({
      ...parcel,
      ...Object.fromEntries(
        dimensions.map((k) => [k, Number(s["default_parcel_" + k])]),
      ),
    }, now);
    return full;
  }
  return parcel;
}
export function bookingQuoteError(
  o: Record<string, unknown>,
  service: unknown,
  parcel: Parcel,
  rate: Record<string, unknown> | undefined,
): string | null {
  if (!o.shipping_quote_id) {
    return "This legacy order has no paid shipping quote. Arrange seller-paid delivery outside this booking flow; do not charge the buyer retrospectively";
  }
  if (
    typeof o.shipping_carrier_name !== "string" ||
    !o.shipping_carrier_name.trim() || o.shipping_currency !== "SGD" ||
    String(service) !== o.shipping_service_id ||
    !sameParcel(parcel, o.shipping_parcel)
  ) return "Service or parcel differs from the paid shipping quote";
  if (
    !rate || rate.carrier_name !== o.shipping_carrier_name ||
    rate.service_id !== o.shipping_service_id ||
    rate.source_currency !== o.shipping_source_currency ||
    Number(rate.source_shipping_amount) !== Number(o.shipping_source_amount) ||
    rate.total_shipping_cents !== o.total_shipping_cents
  ) {
    return "Shipping price changed. Do not book or charge again; arrange seller-paid delivery or contact the customer";
  }
  return null;
}

function sameParcel(a: Parcel, b: unknown) {
  if (!b || typeof b !== "object") return false;
  const other = b as Record<string, unknown>;
  return ["weight_kg", "length_cm", "width_cm", "height_cm"].every((key) =>
    (key !== "weight_kg" && other[key] == null) ||
    (a as unknown as Record<string, unknown>)[key] === other[key]
  );
}
export function retryShippingError(
  existing: Record<string, unknown>,
  checkout: string,
  q: Record<string, unknown> | null,
): string | null {
  if (existing.shipping_checkout_signature !== checkout) {
    return "Checkout items, address or promo changed. Start a new checkout";
  }
  if (!existing.shipping_quote_id) {
    return q && Number(q.buyer_shipping_cents) !== 0
      ? "Delivery fee changed. Start a new checkout"
      : null;
  }
  if (
    !q || q.checkout_signature !== checkout ||
    q.service_id !== existing.shipping_service_id ||
    q.carrier_name !== existing.shipping_carrier_name ||
    q.total_shipping_cents !== existing.total_shipping_cents ||
    q.buyer_shipping_cents !== existing.buyer_shipping_cents ||
    q.seller_shipping_cents !== existing.seller_shipping_cents
  ) return "Accepted shipping fee changed. Start a new checkout";
  return null;
}

// Pickup dates may be rescheduled. The accepted physical parcel cannot change.
export function bookingParcel(
  accepted: unknown,
  requested: unknown,
  now = new Date(),
): Parcel {
  if (!accepted || typeof accepted !== "object") {
    throw new DeliveryValidationError(
      "This order has no accepted shipping parcel",
    );
  }
  const original = accepted as Record<string, unknown>;
  let candidate = requested;
  if (candidate == null) {
    const today = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Singapore",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(now);
    const tomorrow = new Date(today + "T00:00:00Z");
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    candidate = {
      ...original,
      collection_date: String(original.collection_date) > today
        ? original.collection_date
        : tomorrow.toISOString().slice(0, 10),
    };
  }
  const parcel = validateParcel(candidate, now);
  if (!sameParcel(parcel, accepted)) {
    throw new DeliveryValidationError(
      "Packed measurements differ from the accepted shipping quote. Resolve the parcel before booking",
    );
  }
  return parcel;
}
export function checkoutAmountCents(
  merchandise: number,
  buyerShippingCents: number,
): number {
  if (
    !Number.isFinite(merchandise) || merchandise < 0 ||
    !Number.isSafeInteger(buyerShippingCents) || buyerShippingCents < 0
  ) throw new DeliveryValidationError("Invalid checkout amount");
  const cents = Math.round(merchandise * 100) + buyerShippingCents;
  if (!Number.isSafeInteger(cents) || cents <= 0) {
    throw new DeliveryValidationError("Invalid checkout total");
  }
  return cents;
}
export function checkoutMerchandiseCents(
  subtotal: number,
  discount: number,
  gstPercent: number,
  gstIncluded: boolean,
): number {
  if (
    ![subtotal, discount, gstPercent].every(Number.isFinite) || subtotal < 0 ||
    discount < 0 || gstPercent < 0
  ) throw new DeliveryValidationError("Invalid merchandise totals");
  const subtotalCents = Math.round(subtotal * 100);
  const discountCents = Math.min(
    subtotalCents,
    Math.max(0, Math.round(discount * 100)),
  );
  const netCents = subtotalCents - discountCents;
  const taxCents = gstIncluded ? 0 : Math.round(netCents * gstPercent / 100);
  const total = netCents + taxCents;
  if (!Number.isSafeInteger(total)) {
    throw new DeliveryValidationError("Invalid merchandise total");
  }
  return total;
}
