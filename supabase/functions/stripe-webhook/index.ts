// Supabase Edge Function: stripe-webhook
//
// Source of truth for payment confirmation. Orders are created as `pending`
// by create-payment-intent; this webhook flips them to `paid` (or
// `cancelled` on failure) and is idempotent via stripe_payment_intent_id.
//
// Deploy:  supabase functions deploy stripe-webhook --no-verify-jwt
// Secrets: supabase secrets set STRIPE_SECRET_KEY=sk_test_xxx STRIPE_WEBHOOK_SECRET=whsec_xxx

import Stripe from 'https://esm.sh/stripe@17?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-06-20',
});
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
// Prefer the new secret key (set explicitly via `supabase secrets set`)
// over the legacy JWT service_role name the platform auto-injects, so
// this keeps working whether or not legacy JWT-based API keys are later
// disabled project-wide.
const serviceRoleKey =
  Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

// Best-effort push notification via send-order-notification (see that
// function for the full explanation) — service-role-to-service-role call,
// so it's trusted without an extra admin check on the receiving end.
// Never allowed to fail the webhook response back to Stripe: a push that
// doesn't go out is far less costly than Stripe retrying (or giving up on)
// an otherwise-successful payment confirmation.
async function notifyOrderStatus(orderId: string, status: string) {
  try {
    await fetch(`${supabaseUrl}/functions/v1/send-order-notification`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ order_id: orderId, status }),
    });
  } catch (err) {
    console.error('[stripe-webhook] notifyOrderStatus failed', err);
  }
}

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
      const orderId = intent.metadata?.order_id;

      // Prefer metadata order_id; fall back to PI id lookup.
      let query = supabaseAdmin.from('orders').update({ status: 'paid' });
      if (orderId) {
        query = query.eq('id', orderId).eq('status', 'pending');
      } else {
        query = query.eq('stripe_payment_intent_id', intent.id).eq('status', 'pending');
      }
      const { error } = await query;
      if (error) {
        console.error('Failed to mark order paid', intent.id, error);
        return new Response(JSON.stringify({ error: error.message }), { status: 500 });
      }
      if (orderId) {
        await notifyOrderStatus(orderId, 'paid');
      }
      break;
    }
    case 'payment_intent.payment_failed':
    case 'payment_intent.canceled': {
      const intent = event.data.object as Stripe.PaymentIntent;
      const orderId = intent.metadata?.order_id;

      let query = supabaseAdmin.from('orders').update({ status: 'cancelled' });
      if (orderId) {
        query = query.eq('id', orderId).in('status', ['pending', 'paid']);
      } else {
        query = query
          .eq('stripe_payment_intent_id', intent.id)
          .in('status', ['pending', 'paid']);
      }
      const { error } = await query;
      if (error) {
        console.error('Failed to cancel order', intent.id, error);
        return new Response(JSON.stringify({ error: error.message }), { status: 500 });
      }
      break;
    }
    default:
      break;
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
