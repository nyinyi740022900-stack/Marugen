import {
  authenticated,
  corsHeaders,
  DeliveryError,
  json,
  loadOrder,
  loadSender,
} from "../_shared/delivery_api.ts";
import { validateSingaporeAddress } from "../_shared/delivery.ts";
import { getEasyParcelAccessToken } from "../_shared/easyparcel_token.ts";
import { fetchRates, officialFx } from "../_shared/shipping_api.ts";
import { signature } from "../_shared/shipping_finance.ts";
import {
  assertParcelApproval,
  cheapestPickupRate,
  ParcelSubmitError,
  parcelPackingHints,
  providerRejectionReason,
  runParcelBookings,
  validateAllocation,
} from "../_shared/order_parcels.ts";
import {
  loadParcels,
  refreshOrderParcels,
} from "../_shared/order_parcels_api.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { admin } = await authenticated(req);
    const body = await req.json();
    const order = await loadOrder(admin, body.order_id);
    const totals = (total: number) => ({
      total_cents: total,
      buyer_shipping_cents: order.buyer_shipping_cents ?? 0,
      prepaid_shipping_cents: order.total_shipping_cents ?? 0,
      seller_shipping_cents: Math.max(
        0,
        total - (order.buyer_shipping_cents ?? 0),
      ),
      additional_seller_cents: Math.max(
        0,
        total - (order.total_shipping_cents ?? 0),
      ),
    });
    if (body.action === "list") {
      // Product packing data is only a hint. The submitted boxes always require
      // measured dimensions and exact purchase-line quantity allocations.
      const { data: lines, error } = await admin.from("order_items").select(
        "*,product:products(shipping_weight_kg,packed_dimensions),variant:product_variants(shipping_weight_kg,packed_dimensions)",
      ).eq("order_id", order.id);
      if (error) throw error;
      return json({
        parcels: await loadParcels(admin, order.id),
        items: (lines ?? []).map((i) => ({
          order_item_id: i.id,
          product_name: i.product_name,
          option_label: [i.variant_label, i.size_label].filter(Boolean).join(
            " / ",
          ),
          quantity: i.quantity,
          ...parcelPackingHints(i),
        })),
        buyer_shipping_cents: order.buyer_shipping_cents ?? 0,
        prepaid_shipping_cents: order.total_shipping_cents ?? 0,
      });
    }
    if (body.action === "save_plan") {
      const plan = validateAllocation(order.items, body.parcels);
      const { data, error } = await admin.rpc("save_order_parcel_plan", {
        p_order_id: order.id,
        p_parcels: plan,
      });
      if (error) throw new DeliveryError(error.message, 409);
      return json({ parcels: data });
    }
    if (body.action === "refresh") {
      return json({
        parcels: await refreshOrderParcels(admin, order.id, body.parcel_id),
      });
    }
    if (body.action === "discard_plan") {
      const { error } = await admin.rpc("discard_order_parcel_plan", {
        p_order_id: order.id,
      });
      if (error) throw new DeliveryError(error.message, 409);
      return json({ parcels: [] });
    }
    if (body.action === "reset") {
      // Staff must have checked EasyParcel: a timed-out request can still
      // have created a shipment there, and the database cannot see that.
      if (body.confirmed_not_in_easyparcel !== true) {
        throw new DeliveryError(
          "Confirm EasyParcel has no shipment for this order before retrying",
          409,
        );
      }
      const { data, error } = await admin.rpc("reset_unsubmitted_parcel_plan", {
        p_order_id: order.id,
      });
      if (error) throw new DeliveryError(error.message, 409);
      return json({ parcels: data });
    }
    if (!["quote", "book"].includes(body.action)) {
      throw new DeliveryError("Unknown parcel action");
    }
    const parcels = await loadParcels(admin, order.id);
    if (parcels.length < 2 || parcels.some((p) => p.state !== "draft")) {
      throw new DeliveryError(
        "Save an unsubmitted packing plan before quoting or booking",
        409,
      );
    }
    validateAllocation(order.items, parcels);
    // One official exchange snapshot for the entire plan, never the buyer's
    // historical checkout conversion. These are current seller spending quotes.
    let fx: ReturnType<typeof officialFx> | undefined;
    const quotes: {
      id: string;
      service_id: string;
      carrier_name: string;
      quoted_total_cents: number;
      source_currency: string;
      source_shipping_amount: number;
      fx_rate: number;
    }[] = [];
    for (const parcel of parcels) {
      const rate = cheapestPickupRate(
        await fetchRates(
          admin,
          order.shipping_address,
          parcel,
          () => fx ??= officialFx(),
        ),
      );
      quotes.push({
        id: parcel.id,
        service_id: rate.service_id,
        carrier_name: rate.carrier_name,
        quoted_total_cents: rate.total_shipping_cents,
        source_currency: rate.source_currency,
        source_shipping_amount: rate.source_shipping_amount,
        fx_rate: rate.fx_rate,
      });
    }
    const total = quotes.reduce((s, q) => s + q.quoted_total_cents, 0);
    if (!Number.isSafeInteger(total) || total <= 0) {
      throw new DeliveryError("Invalid aggregate quote", 502);
    }
    const quoteSignature = await signature(JSON.stringify({
      plan: parcels.map((p) => ({
        id: p.id,
        items: p.items,
        weight_kg: p.weight_kg,
        length_cm: p.length_cm,
        width_cm: p.width_cm,
        height_cm: p.height_cm,
        collection_date: p.collection_date,
      })),
      quotes,
    }));
    if (body.action === "quote") {
      const expires = new Date(Date.now() + 10 * 60 * 1000).toISOString();
      const { error } = await admin.rpc("quote_order_parcel_plan", {
        p_order_id: order.id,
        p_quotes: quotes,
        p_signature: quoteSignature,
        p_expires_at: expires,
      });
      if (error) throw new DeliveryError(error.message, 409);
      return json({
        parcels: await loadParcels(admin, order.id),
        ...totals(total),
        expires_at: expires,
        quote_signature: quoteSignature,
      });
    }
    try {
      assertParcelApproval(
        parcels,
        quoteSignature,
        total,
        body.approved_total_cents,
        body.approved_quote_signature,
      );
    } catch (error) {
      throw new DeliveryError((error as Error).message, 409);
    }
    // Validate local prerequisites before claiming, then claim every box in one
    // transaction before the first external submission. There is no retry path.
    const sender = await loadSender(admin);
    const receiver = validateSingaporeAddress(order.shipping_address);
    const token = await getEasyParcelAccessToken(admin);
    await runParcelBookings(parcels, {
      claim: async () => {
        const { data, error } = await admin.rpc("claim_order_parcel_plan", {
          p_order_id: order.id,
          p_signature: quoteSignature,
          p_approved_total_cents: body.approved_total_cents,
        });
        if (error) {
          throw new DeliveryError(error.message, 409);
        }
        return data === true;
      },
      submit: async (p) => {
        const quote = quotes.find((q) => q.id === p.id)!;
        const dimensions = {
          weight: p.weight_kg,
          length: p.length_cm,
          width: p.width_cm,
          height: p.height_cm,
        };
        const content = p.items.map(
          (allocation: { order_item_id: string; quantity: number }) => {
            const line = order.items.find((i: { id: string }) =>
              i.id === allocation.order_item_id
            );
            return `${
              [line.product_name, line.variant_label, line.size_label].filter(
                Boolean,
              ).join(" / ")
            } x${allocation.quantity}`;
          },
        ).join("; ");
        const value = p.items.reduce(
          (sum: number, a: { order_item_id: string; quantity: number }) =>
            sum + Number(
                order.items.find((i: { id: string }) =>
                  i.id === a.order_item_id
                ).unit_price,
              ) * a.quantity,
          0,
        );
        const response = await fetch(
          "https://api.easyparcel.com/open_api/2026-06/shipment/submit_orders",
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${token}`,
              "Content-Type": "application/json",
            },
            signal: AbortSignal.timeout(30000),
            body: JSON.stringify({
              shipment: [{
                reference: p.id,
                auto_apply_coupon: false,
                service_id: quote.service_id,
                collection_date: p.collection_date,
                ...dimensions,
                item: [{
                  content,
                  ...dimensions,
                  currency_code: "SGD",
                  value,
                  quantity: 1,
                }],
                sender,
                receiver: {
                  name: receiver.recipient_name,
                  phone_number_country_code: "SG",
                  phone_number: receiver.phone,
                  address_1: receiver.line1,
                  address_2: receiver.line2,
                  postcode: receiver.postal_code,
                  city: receiver.city,
                  subdivision_code: "",
                  country_code: "SG",
                },
              }],
            }),
          },
        );
        const result = await response.json();
        const shipment = result?.data?.[0]?.shipments?.[0];
        const paymentRequired = [
          shipment?.payment_status,
          shipment?.order_status,
          shipment?.status,
          shipment?.message,
          result?.message,
        ].some((s) =>
          typeof s === "string" &&
          /waiting payment|expired \(unpaid\)|unpaid|payment required/i.test(s)
        );
        if (
          !paymentRequired &&
          (!response.ok || (result.status_code && result.status_code !== 200) ||
            shipment?.status !== "success")
        ) {
          const reason = providerRejectionReason(response.status, result);
          console.error("[order-parcels] submission rejected", order.id, reason);
          throw new ParcelSubmitError(reason);
        }
        return {
          trackingNumber: typeof shipment?.awb_number === "string"
            ? shipment.awb_number
            : null,
          shipmentId: typeof shipment?.shipment_number === "string"
            ? shipment.shipment_number
            : null,
          awbUrl: typeof shipment?.awb_url === "string"
            ? shipment.awb_url
            : null,
          paymentRequired,
        };
      },
      persist: async (p, outcome) => {
        const { data, error } = await admin.from("order_parcels").update({
          ...outcome,
          tracking_status: outcome.state === "booked"
            ? "Booked"
            : outcome.state === "payment_required"
            ? "Shipping payment required"
            : "Needs attention",
          tracking_updated_at: new Date().toISOString(),
        }).eq("id", p.id).eq("state", "booking").select("id").maybeSingle();
        if (error || !data) {
          throw new DeliveryError(
            "Claim retained; check the existing EasyParcel shipment before any further action",
            502,
          );
        }
      },
    });
    const booked = await loadParcels(admin, order.id);
    return json({
      parcels: booked,
      needs_attention: booked.some((p) => p.state !== "booked"),
      ...totals(total),
    });
  } catch (error) {
    // Provider bodies, PII and credentials never leave this endpoint or logs.
    const status = error instanceof DeliveryError ? error.status : 400;
    const message = error instanceof Error
      ? error.message
      : "Parcel request failed";
    return json({ error: message }, status);
  }
});
