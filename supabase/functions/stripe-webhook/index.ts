// Supabase Edge Function: stripe-webhook
//
// Source of truth for payment confirmation — Stripe calls this directly
// (not the app), so a flaky connection on the customer's phone can't leave
// an order stuck as "pending" after money has actually moved.
//
// Deploy:  supabase functions deploy stripe-webhook --no-verify-jwt
// Secrets: supabase secrets set STRIPE_SECRET_KEY=sk_test_xxx STRIPE_WEBHOOK_SECRET=whsec_xxx
// Then in the Stripe Dashboard → Developers → Webhooks, add an endpoint
// pointing at this function's URL, subscribed to:
//   payment_intent.succeeded, payment_intent.payment_failed

import Stripe from 'https://esm.sh/stripe@17?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-06-20',
});
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

Deno.serve(async (req) => {
  const signature = req.headers.get('stripe-signature');
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature ?? '', webhookSecret);
  } catch (err) {
    return new Response(`Webhook signature verification failed: ${err}`, { status: 400 });
  }

  switch (event.type) {
    case 'payment_intent.succeeded': {
      const intent = event.data.object as Stripe.PaymentIntent;
      await supabaseAdmin
        .from('orders')
        .update({ status: 'paid' })
        .eq('stripe_payment_intent_id', intent.id);
      break;
    }
    case 'payment_intent.payment_failed': {
      const intent = event.data.object as Stripe.PaymentIntent;
      await supabaseAdmin
        .from('orders')
        .update({ status: 'cancelled' })
        .eq('stripe_payment_intent_id', intent.id);
      break;
    }
    default:
      // Ignore other event types.
      break;
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
