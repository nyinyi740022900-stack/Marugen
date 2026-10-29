// Supabase Edge Function: stripe-webhook
//
// Source of truth for payment confirmation. Orders are created as `pending`
// by create-payment-intent; this webhook flips them to `paid` (or
// `cancelled` only after verified Stripe cancellation) and is idempotent via stripe_payment_intent_id.
//
// Deploy:  supabase functions deploy stripe-webhook --no-verify-jwt
// Secrets: supabase secrets set STRIPE_SECRET_KEY=sk_test_xxx STRIPE_WEBHOOK_SECRET=whsec_xxx

import Stripe from "https://esm.sh/stripe@17?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { syncOrderRefunds } from "../_shared/refund_lifecycle.ts";
import { createRefundPort } from "../_shared/refund_port.ts";
import { applyPaymentEvent } from "../_shared/payment_lifecycle.ts";
import { createPaymentPort } from "../_shared/payment_port.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-06-20",
});
const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
// Prefer the new secret key (set explicitly via `supabase secrets set`)
// over the legacy JWT service_role name the platform auto-injects, so
// this keeps working whether or not legacy JWT-based API keys are later
// disabled project-wide.
const serviceRoleKey = Deno.env.get("SB_SERVICE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

const paymentPort = createPaymentPort(
  supabaseAdmin,
  stripe,
  supabaseUrl,
  serviceRoleKey,
);

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature ?? "",
      webhookSecret,
    );
  } catch (err) {
    return new Response(`Webhook signature verification failed: ${err}`, {
      status: 400,
    });
  }

  try {
    if (
      event.type === "payment_intent.succeeded" ||
      event.type === "payment_intent.canceled" ||
      event.type === "payment_intent.payment_failed"
    ) {
      const intent = event.data.object as Stripe.PaymentIntent;
      await applyPaymentEvent(event.type, intent.id, paymentPort);
    } else if (
      ["refund.created", "refund.updated", "refund.failed", "charge.refunded"]
        .includes(event.type)
    ) {
      // Fetch current Stripe state instead of trusting delivery order/payload.
      const object = event.data.object as Stripe.Refund | Stripe.Charge;
      const intentId = typeof object.payment_intent === "string"
        ? object.payment_intent
        : object.payment_intent?.id;
      if (intentId) {
        await syncOrderRefunds(
          intentId,
          createRefundPort(supabaseAdmin, stripe, supabaseUrl, serviceRoleKey),
        );
      }
    }
  } catch (err) {
    console.error("Payment reconciliation failed", event.id, err);
    // Stripe retries failures; a zero-row/terminal conflict is never silently accepted.
    return new Response(
      JSON.stringify({ error: "Payment reconciliation required" }),
      { status: 500 },
    );
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
