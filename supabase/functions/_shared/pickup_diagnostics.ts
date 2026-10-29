import { parseTrackingEvidence } from "./tracking_evidence.ts";
// Read-only owner diagnostics. Wallet balance is context, never proof of why a
// particular shipment is delayed. Never retry submission from this flow.
type Order = {
  qxpress_tracking_no?: string | null;
  easyparcel_shipment_id?: string | null;
  easyparcel_booking_state?: string | null;
  tracking_status_detail?: string | null;
};
type Evidence = {
  code: number | null;
  text: string;
  collectionDate?: string | null;
};
export function isSampleTracking(number: unknown): boolean {
  return typeof number === "string" && /^EPSAMPLE/i.test(number.trim());
}
export function diagnosePickup(
  order: Order,
  evidence: Evidence | null,
  today: string,
) {
  const result = (
    reason: string,
    title: string,
    message: string,
    action: string,
  ) => ({ reason, title, message, action });
  if (
    isSampleTracking(order.qxpress_tracking_no) ||
    isSampleTracking(order.easyparcel_shipment_id)
  ) {
    return result(
      "sample_tracking",
      "Sample tracking detected",
      "This sample number is not proof of a live courier booking. Pickup has not been confirmed.",
      "Reconnect using the live EasyParcel account, then verify this order in All Parcels before arranging delivery. Do not duplicate an existing booking.",
    );
  }
  if (!evidence && order.easyparcel_booking_state === "needs_attention") {
    if (order.tracking_status_detail === "booking_issue:insufficient_credit") {
      return result(
        "insufficient_credit",
        "Booking rejected: insufficient credit",
        "At the last booking attempt, EasyParcel explicitly reported insufficient credit. Pickup was not confirmed.",
        "Check the existing order in EasyParcel before completing payment or arranging delivery. Do not duplicate a booking.",
      );
    }
    if (order.tracking_status_detail === "booking_issue:invalid_details") {
      return result(
        "invalid_details",
        "Booking details need attention",
        "EasyParcel rejected required parcel, address or pickup details at the last booking attempt.",
        "Check the existing order and correct its details in EasyParcel before arranging delivery.",
      );
    }
  }
  if (!evidence) {
    return result(
      "unverified",
      "Pickup not verified",
      "The current booking or reason for delay could not be verified. A low wallet balance alone does not explain a missed pickup.",
      "Check this shipment and its payment in EasyParcel. Do not book again until the existing booking is checked.",
    );
  }
  const status = evidence.text.trim().toLowerCase();
  if (["waiting payment", "expired (unpaid)"].includes(status)) {
    return result(
      "payment_required",
      "Shipping payment required",
      "EasyParcel reports that this shipment is unpaid.",
      "Open the existing shipment in EasyParcel and check its payment. Adding credit alone may not complete an unpaid order.",
    );
  }
  if (evidence.code === 5) {
    return result(
      "delivered",
      "Delivered",
      "EasyParcel reports delivery to the recipient.",
      "No pickup action is needed.",
    );
  }
  if (evidence.code === 11) {
    return result(
      "dropped_off",
      "Parcel dropped off",
      "EasyParcel reports a drop-off handover.",
      "Follow the tracking updates; a door pickup is not needed.",
    );
  }
  if ([3, 4].includes(evidence.code ?? -1)) {
    return result(
      "collected",
      "Collected by courier",
      "EasyParcel reports collection or transit.",
      "Follow the tracking updates for delivery progress.",
    );
  }
  if (evidence.code === 0) {
    return result(
      "cancelled",
      "Shipment cancelled",
      "EasyParcel reports that this shipment is cancelled.",
      "Check cancellation and payment details before arranging another shipment.",
    );
  }
  if (evidence.code === 6) {
    return result(
      "returned",
      "Parcel returned",
      "EasyParcel reports that the parcel was returned.",
      "Check the return details with EasyParcel before arranging delivery.",
    );
  }
  if (evidence.code === 8) {
    return result(
      "on_hold",
      "Shipment on hold",
      "EasyParcel reports a hold but has not supplied a verified cause here.",
      "Open the shipment in EasyParcel or contact support for the reason.",
    );
  }
  if ([2, 7].includes(evidence.code ?? -1)) {
    const day = evidence.collectionDate?.slice(0, 10);
    if (day && /^\d{4}-\d{2}-\d{2}$/.test(day) && day < today) {
      return result(
        "pickup_overdue",
        "Pickup date passed",
        "The scheduled pickup date has passed and collection is not confirmed. EasyParcel has not supplied the cause here.",
        "Contact EasyParcel about this existing shipment. Do not create another booking to retry pickup.",
      );
    }
    return result(
      "awaiting_pickup",
      "Awaiting courier pickup",
      "EasyParcel reports collection pending or scheduling in progress. Collection is not confirmed.",
      "Keep the labelled parcel ready. Check the pickup schedule in EasyParcel; contact support if the window is missed.",
    );
  }
  return result(
    "unverified",
    "Pickup not verified",
    "EasyParcel returned a status that does not confirm collection or explain a delay.",
    "Check the existing shipment in EasyParcel before taking further action.",
  );
}
export function readSgdWallet(
  input: unknown,
): { balance: number; free_credit: number | null } | null {
  if (!input || typeof input !== "object") return null;
  const body = input as Record<string, unknown>;
  function amount(rows: unknown) {
    if (!Array.isArray(rows)) return null;
    const row = rows.find((r) => r?.currency === "SGD");
    if (
      !row || !["number", "string"].includes(typeof row.balance) ||
      String(row.balance).trim() === ""
    ) return null;
    const value = Number(row.balance);
    return Number.isFinite(value) && value >= 0 ? value : null;
  }
  const balance = amount(body.wallet);
  return balance === null
    ? null
    : { balance, free_credit: amount(body.free_credit_wallet) };
}
export async function checkPickup(
  token: string,
  order: Order,
  now = new Date(),
  fetcher: typeof fetch = fetch,
) {
  async function read(path: string, body?: unknown) {
    try {
      const response = await fetcher(
        `https://api.easyparcel.com/open_api/2026-09/${path}`,
        {
          method: body ? "POST" : "GET",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          ...(body ? { body: JSON.stringify(body) } : {}),
          signal: AbortSignal.timeout(12000),
        },
      );
      const json = await response.json();
      if (
        response.ok && path === "shipment/details" &&
        json.status_code === 400 &&
        json.message ===
          `No Order with shipment_number ${order.easyparcel_shipment_id} found from this account`
      ) {
        return { not_found_in_account: true };
      }
      return response.ok && json.status_code === 200 ? json.data : null;
    } catch {
      return null;
    }
  }
  const sample = isSampleTracking(order.qxpress_tracking_no) ||
    isSampleTracking(order.easyparcel_shipment_id);
  const [wallet, shipment] = await Promise.all([
    read("wallet"),
    sample ? null : order.easyparcel_shipment_id
      ? read("shipment/details", {
        shipment_number: order.easyparcel_shipment_id,
      })
      : order.qxpress_tracking_no
      ? read("shipment/tracking_status", {
        awb_numbers: [order.qxpress_tracking_no],
      })
      : null,
  ]);
  let evidence: Evidence | null = null;
  if (Array.isArray(shipment) && order.easyparcel_shipment_id) {
    const item = shipment.find((s) =>
      s.shipment_number === order.easyparcel_shipment_id
    );
    const d = item?.shipment_details;
    if (
      d &&
      (!order.qxpress_tracking_no || d.awb_number === order.qxpress_tracking_no)
    ) {
      evidence = {
        code: typeof d.shipment_status_code === "number"
          ? d.shipment_status_code
          : null,
        text: typeof d.shipment_status === "string" ? d.shipment_status : "",
        collectionDate: typeof d.coll_date === "string" ? d.coll_date : null,
      };
    }
  } else if (shipment?.results && order.qxpress_tracking_no) {
    try {
      const tracking = parseTrackingEvidence(
        shipment,
        order.qxpress_tracking_no,
      );
      evidence = { code: tracking.code, text: tracking.text ?? "" };
    } catch {
      evidence = null;
    }
  }
  // Provider date-times are UTC. Compare collection day after conversion to SG.
  if (evidence?.collectionDate) {
    const parsed = new Date(evidence.collectionDate.replace(" ", "T") + "Z");
    evidence.collectionDate = Number.isFinite(parsed.getTime())
      ? singaporeDay(parsed)
      : null;
  }
  const diagnostic = !sample && shipment?.not_found_in_account === true
    ? {
      reason: "not_found_in_account",
      title: "Shipment not found in connected account",
      message:
        "EasyParcel could not find this shipment in the currently connected account. Pickup is not confirmed.",
      action:
        "Check the selected Live account and the original booking in EasyParcel before arranging delivery. Do not duplicate an existing shipment.",
    }
    : diagnosePickup(order, evidence, singaporeDay(now));
  return {
    ...diagnostic,
    wallet: readSgdWallet(wallet),
    provider_status: evidence?.text || null,
    collection_date: evidence?.collectionDate || null,
    checked_at: now.toISOString(),
    verified: evidence !== null,
  };
}
function singaporeDay(date: Date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Singapore",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

export function bookingFailureCode(body: unknown): string | null {
  if (!body || typeof body !== "object") return null;
  const b = body as Record<string, unknown>;
  // Inspect only error fields, never address/content strings or arbitrary raw payloads.
  const errors: unknown[] = [
    b.message,
    ...(Array.isArray(b.errors) ? b.errors : []),
  ];
  if (Array.isArray(b.data)) {
    for (const row of b.data) {
      if (Array.isArray(row?.shipments)) {
        for (const shipment of row.shipments) {
          if (
            shipment?.status !== "success" && Array.isArray(shipment?.errors)
          ) errors.push(...shipment.errors);
        }
      }
    }
  }
  const text = errors.filter((e) => typeof e === "string").join(" ")
    .toLowerCase();
  if (
    /insufficient (credit|balance|funds)|not enough (credit|balance|funds)/
      .test(text)
  ) return "insufficient_credit";
  if (
    /(postcode|collection date|weight|height|length|width|receiver|sender).*(required|invalid)/
      .test(text)
  ) return "invalid_details";
  return null;
}
export class BookingRejectedError extends Error {
  constructor(public readonly issue: string | null) {
    super(
      "EasyParcel rejected the booking; check the existing order before retrying.",
    );
  }
}
