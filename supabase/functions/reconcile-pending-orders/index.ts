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

import Stripe from 'https://esm.sh/stripe@17?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-06-20',
});

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey =
  Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const admin = createClient(supabaseUrl, serviceRoleKey);

const RECONCILE_AFTER_MS = 5 * 60 * 1000;

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
    console.error('[reconcile-pending-orders] notifyOrderStatus failed', err);
  }
}

Deno.serve(async (req) => {
  // Exact match, not a substring check — see send-order-notification for
  // why `includes` would be unsafe here.
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!serviceRoleKey || authHeader !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403 });
  }

  const cutoff = new Date(Date.now() - RECONCILE_AFTER_MS).toISOString();
  const { data: staleOrders, error } = await admin
    .from('orders')
    .select('id, stripe_payment_intent_id')
    .eq('status', 'pending')
    .not('stripe_payment_intent_id', 'is', null)
    .lt('created_at', cutoff);

  if (error) {
    console.error('[reconcile-pending-orders] query failed', error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  let reconciled = 0;
  for (const order of staleOrders ?? []) {
    try {
      const intent = await stripe.paymentIntents.retrieve(
        order.stripe_payment_intent_id as string,
      );
      if (intent.status !== 'succeeded') continue;

      // Same `.eq('status', 'pending')` idempotency guard stripe-webhook
      // uses on its own update — this can never race a webhook that
      // already landed (or a concurrent reconcile run) into a double
      // notify, since only the write that actually flips the row reports
      // a match.
      const { data: updated, error: updateError } = await admin
        .from('orders')
        .update({ status: 'paid' })
        .eq('id', order.id)
        .eq('status', 'pending')
        .select('id')
        .maybeSingle();

      if (updateError) {
        console.error('[reconcile-pending-orders] failed to mark paid', order.id, updateError);
        continue;
      }
      if (updated) {
        reconciled++;
        await notifyOrderStatus(order.id, 'paid');
      }
    } catch (err) {
      console.error('[reconcile-pending-orders] stripe lookup failed', order.id, err);
    }
  }

  return new Response(
    JSON.stringify({ checked: staleOrders?.length ?? 0, reconciled }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
