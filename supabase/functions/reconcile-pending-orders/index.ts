// Supabase Edge Function: reconcile-pending-orders
//
// Companion to stripe-webhook and the cancel-stale-pending-orders cron job
// (0014_stale_order_cleanup.sql). That job blindly cancels any order still
// `pending` after 30 minutes, assuming stripe-webhook never fired — but if
// the webhook delivery itself failed (network blip, brief Supabase outage)
// while the customer's card WAS actually charged, blind cancellation would
// silently release the shop's stock while the customer has already paid.
//
// Called on a schedule by pg_cron via pg_net (see
// 0048_reconcile_pending_orders.sql) — never from the Flutter app. For
// every order still `pending` more than 5 minutes after checkout, asks
// Stripe directly whether its PaymentIntent actually succeeded; if so,
// marks the order `paid` itself — mirroring exactly what stripe-webhook's
// `payment_intent.succeeded` branch does — instead of waiting on a webhook
// delivery that may never arrive. Runs well inside the 30-minute window
// before cancel-stale-pending-orders would otherwise see (and wrongly
// cancel) the same order.
//
// Auth: service-role only. Deployed with --no-verify-jwt (the cron job
// carries no user session), so this checks the Authorization header
// itself against the service-role key — same shared-secret pattern
// stripe-webhook uses via Stripe's own signature instead.
//
// Deploy:  supabase functions deploy reconcile-pending-orders --no-verify-jwt
// Secrets: STRIPE_SECRET_KEY (already set for create-payment-intent/stripe-webhook)

import Stripe from "https://esm.sh/stripe@17?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  applyPaymentEvent,
  cancelPendingPayment,
} from "../_shared/payment_lifecycle.ts";
import { syncOrderRefunds } from "../_shared/refund_lifecycle.ts";
import { createRefundPort } from "../_shared/refund_port.ts";
import { createPaymentPort } from "../_shared/payment_port.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-06-20",
});

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SB_SERVICE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, serviceRoleKey);

const RECONCILE_AFTER_MS = 5 * 60 * 1000;

const port = createPaymentPort(admin, stripe, supabaseUrl, serviceRoleKey);
Deno.serve(async (req) => {
  // Exact match, not a substring check — see send-order-notification for
  // why `includes` would be unsafe here.
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!serviceRoleKey || authHeader !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
    });
  }

  const cutoff = new Date(Date.now() - RECONCILE_AFTER_MS).toISOString();
  const { data: staleOrders, error } = await admin
    .from("orders")
    .select("id, stripe_payment_intent_id, created_at")
    .eq("status", "pending")
    .not("stripe_payment_intent_id", "is", null)
    .lt("created_at", cutoff);

  if (error) {
    console.error("[reconcile-pending-orders] query failed", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
    });
  }

  let reconciled = 0;
  let failures = 0;
  for (const order of staleOrders ?? []) {
    try {
      const intent = await stripe.paymentIntents.retrieve(
        order.stripe_payment_intent_id as string,
      );
      if (intent.status === "succeeded" || intent.status === "canceled") {
        await applyPaymentEvent(
          intent.status === "succeeded"
            ? "payment_intent.succeeded"
            : "payment_intent.canceled",
          intent.id,
          port,
        );
        reconciled++;
      } else if (
        Date.now() - new Date(order.created_at).getTime() > 30 * 60 * 1000 &&
        ["requires_payment_method", "requires_confirmation", "requires_action"]
          .includes(intent.status)
      ) {
        await cancelPendingPayment(order.id, port);
        reconciled++;
      }
    } catch (err) {
      failures++;
      console.error(
        "[reconcile-pending-orders] stripe lookup failed",
        order.id,
        err,
      );
    }
  }

  // Recover asynchronous refund completions when webhook delivery is delayed.
  // This path only reads Stripe; it never creates or retries a refund.
  const { data: pendingRefunds, error: refundQueryError } = await admin
    .from("orders").select("id, stripe_payment_intent_id")
    .in("refund_status", ["pending", "requires_action"])
    .not("stripe_payment_intent_id", "is", null);
  if (refundQueryError) {
    failures++;
    console.error("Refund reconciliation query failed", refundQueryError);
  }
  let refundsReconciled = 0;
  for (const order of pendingRefunds ?? []) {
    try {
      await syncOrderRefunds(
        order.stripe_payment_intent_id,
        createRefundPort(admin, stripe, supabaseUrl, serviceRoleKey),
      );
      refundsReconciled++;
    } catch (error) {
      failures++;
      console.error("Refund reconciliation failed", order.id, error);
    }
  }
  return new Response(
    JSON.stringify({
      checked: staleOrders?.length ?? 0,
      reconciled,
      refundsReconciled,
      failures,
    }),
    {
      status: failures > 0 ? 500 : 200,
      headers: { "Content-Type": "application/json" },
    },
  );
});
