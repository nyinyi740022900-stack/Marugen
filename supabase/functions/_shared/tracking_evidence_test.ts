import { parseTrackingEvidence } from "./tracking_evidence.ts";
function eq(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
Deno.test("tracking evidence selects matching AWB rather than first result", () => {
  const result = parseTrackingEvidence({
    results: [{
      status: "success",
      awb_number: "OTHER",
      latest_shipment_status_code: 5,
    }, {
      status: "success",
      awb_number: "AWB",
      shipment_number: "SHIP",
      latest_shipment_status_code: 3,
      latest_tracking_status: "Collected",
    }],
  }, "AWB");
  eq(result.code, 3);
  eq(result.shipmentId, "SHIP");
});
Deno.test("missing or mismatched AWB cannot authorize a lifecycle change", () => {
  for (const awb of [undefined, "OTHER"]) {
    let rejected = false;
    try {
      parseTrackingEvidence({
        results: [{
          status: "success",
          awb_number: awb,
          latest_shipment_status_code: 5,
        }],
      }, "AWB");
    } catch {
      rejected = true;
    }
    eq(rejected, true);
  }
});
Deno.test("unpaid evidence cannot authorize false delivery", () => {
  eq(
    parseTrackingEvidence({
      results: [{
        status: "success",
        awb_number: "AWB",
        latest_shipment_status_code: 5,
        latest_tracking_status: "Waiting Payment",
      }],
    }, "AWB").code,
    null,
  );
});
Deno.test("newest carrier event beats EasyParcel's stale latest summary (verified TracX regression)", () => {
  const result = parseTrackingEvidence({
    results: [{
      status: "success",
      awb_number: "AWB",
      shipment_number: "SHIP",
      latest_shipment_status_code: 7,
      latest_tracking_status: "Schedule In Arrangement",
      latest_event_date: "2026-10-23T07:15:26.442Z",
      status_log: [{
        location: "Singapore Hub",
        event_date: "2026-10-24 11:04:02",
        tracking_status: "Pickup Done",
        shipment_status_code: 3,
      }, {
        event_date: "2026-10-23 16:15:26",
        tracking_status: "Received Shipping Order",
        shipment_status_code: 7,
      }, {
        event_date: "2026-10-23T07:15:26.442Z",
        tracking_status: "Schedule In Arrangement",
        shipment_status_code: 7,
      }],
    }],
  }, "AWB");
  eq(result.code, 3);
  eq(result.text, "Pickup Done");
  eq(result.location, "Singapore Hub");
  eq(result.eventAt, "2026-10-24T03:04:02.000Z");
});
Deno.test("carrier logs are sorted by explicit-offset or Singapore local timestamps, never array order", () => {
  const result = parseTrackingEvidence({
    results: [{
      status: "success",
      awb_number: "AWB",
      latest_shipment_status_code: 7,
      latest_event_date: "2026-10-23T00:00:00Z",
      status_log: [{
        event_date: "2026-10-24T04:00:00Z",
        shipment_status_code: 4,
        tracking_status: "In Transit",
      }, {
        event_date: "2026-10-24 11:04:02",
        shipment_status_code: 3,
        tracking_status: "Pickup Done",
      }],
    }],
  }, "AWB");
  eq(result.code, 4);
  eq(result.eventAt, "2026-10-24T04:00:00.000Z");
});
Deno.test("new hold or return event remains distinct from older delivered/transit; undated log cannot invent delivery", () => {
  for (const code of [8, 6]) {
    const result = parseTrackingEvidence({
      results: [{
        status: "success",
        awb_number: "AWB",
        latest_shipment_status_code: 4,
        latest_event_date: "2026-10-23T00:00:00Z",
        status_log: [{
          event_date: "2026-10-24 11:04:02",
          shipment_status_code: code,
          tracking_status: "Exception",
        }, {
          event_date: "broken",
          shipment_status_code: 5,
          tracking_status: "Delivered",
        }],
      }],
    }, "AWB");
    eq(result.code, code);
  }
});
Deno.test("unpaid pending shipment keeps its code so the parcel can require payment", () => {
  eq(
    parseTrackingEvidence({
      results: [{
        status: "success",
        awb_number: "AWB",
        latest_shipment_status_code: 7,
        latest_tracking_status: "Waiting Payment",
      }],
    }, "AWB").code,
    7,
  );
});
