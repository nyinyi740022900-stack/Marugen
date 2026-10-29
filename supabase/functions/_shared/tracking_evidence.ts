type ProviderRow = Record<string, unknown>;
function row(value: unknown): ProviderRow {
  return value && typeof value === "object" ? value as ProviderRow : {};
}
// This Singapore integration receives ISO offsets in EasyParcel's summary and
// Singapore wall-clock times from TracX's carrier logs. Never use server TZ.
function eventTime(value: unknown): string | null {
  if (typeof value !== "string") return null;
  let date = value.trim().replace(" ", "T");
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$/.test(date)) {
    date += "+08:00";
  }
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/i.test(
      date,
    )
  ) return null;
  const parsed = Date.parse(date);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : null;
}
export function parseTrackingEvidence(data: unknown, number: string) {
  const results = row(data).results;
  const result = Array.isArray(results)
    ? results.map(row).find((r) =>
      r.status === "success" && r.awb_number === number
    )
    : null;
  if (!result) {
    throw new Error("EasyParcel tracking identity could not be verified");
  }
  const summary = {
    code: result.latest_shipment_status_code,
    text: result.latest_tracking_status,
    location: null as unknown,
    eventAt: eventTime(result.latest_event_date),
  };
  const events = Array.isArray(result.status_log)
    ? result.status_log.map(row).map((event) => ({
      code: event.shipment_status_code,
      text: event.tracking_status,
      location: event.location,
      eventAt: eventTime(event.event_date),
    })).filter((event) => event.eventAt !== null)
    : [];
  // Carrier events with dates win a tie; an undated/malformed log cannot create
  // a delivery promotion. latest_* is known to lag the real carrier history.
  const latest =
    [...events, summary].filter((event) => event.eventAt !== null).sort((
      a,
      b,
    ) => Date.parse(b.eventAt!) - Date.parse(a.eventAt!))[0] ?? summary;
  const unpaid = ["waiting payment", "expired (unpaid)"].includes(
    String(latest.text ?? "").trim().toLowerCase(),
  );
  return {
    number,
    returnedNumber: number,
    shipmentId: typeof result.shipment_number === "string"
      ? result.shipment_number
      : null,
    code: !(unpaid && [3, 4, 5, 6, 11].includes(latest.code as number)) &&
        typeof latest.code === "number" &&
        Number.isInteger(latest.code)
      ? latest.code
      : null,
    text: typeof latest.text === "string" ? latest.text : null,
    location: typeof latest.location === "string" ? latest.location : null,
    eventAt: latest.eventAt,
  };
}
