// Supabase Edge Function: stripe-refund
//
// Admin-only. Issues a real Stripe refund for an order's PaymentIntent,
// then flips the order to `refunded` — replacing the previous behaviour
// where admin_orders_screen.dart's "Mark as refunded" action just relabeled
// the status column with no money ever moving. `refunded` in this app now
// always means Stripe actually returned the customer's money.
//
// Idempotency: uses an `idempotencyKey` derived from the order id on the
// Stripe call itself, so a double-tap or retry can never create two Stripe
// refunds for the same order — Stripe returns the original refund object
// instead. The `orders.status = 'paid'/'packing'/'shipped'/'delivered'`
// check below (mirroring validNextStatuses() in lib/shared/models/
// order.dart) additionally stops a second attempt once the DB already
// shows `refunded`.
//
// Deploy:   supabase functions deploy stripe-refund
// Secrets:  STRIPE_SECRET_KEY (already set for create-payment-intent/stripe-webhook)

import Stripe from 'https://esm.sh/stripe@17?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-06-20',
});

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SB_ANON_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceRoleKey =
  Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonError(message: string, status: number) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Same pattern stripe-webhook/easyparcel-book-shipment use for their own
// server-to-server calls — best-effort, never allowed to fail this
// request just because the push notification hiccuped.
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
    console.error('[stripe-refund] notifyOrderStatus failed', err);
  }
}

// Statuses `validNextStatuses()` (lib/shared/models/order.dart) allows to
// move to `refunded` — mirrored here so a bad request never even reaches
// Stripe, and enforced again by the DB's forward-only trigger
// (0030_order_status_forward_only.sql) as the final authority.
const REFUNDABLE_STATUSES = new Set(['paid', 'packing', 'shipped', 'delivered']);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonError('Missing Authorization header', 401);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) return jsonError('Unauthorized', 401);

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: profile } = await admin
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
    if (!profile || (profile.role !== 'staff' && profile.role !== 'owner')) {
      return jsonError('Admin access required', 403);
    }

    const { order_id, reason } = await req.json();
    if (!order_id) return jsonError('order_id is required', 400);

    const { data: order } = await admin
      .from('orders')
      .select('id, status, total, stripe_payment_intent_id')
      .eq('id', order_id)
      .maybeSingle();
    if (!order) return jsonError('Order not found', 404);

    if (!REFUNDABLE_STATUSES.has(order.status)) {
      return jsonError(
        order.status === 'refunded'
          ? 'This order has already been refunded.'
          : `Order in status "${order.status}" cannot be refunded.`,
        409,
      );
    }
    if (!order.stripe_payment_intent_id) {
      return jsonError('This order has no Stripe payment to refund.', 400);
    }

    let refund: Stripe.Refund;
    try {
      refund = await stripe.refunds.create(
        {
          payment_intent: order.stripe_payment_intent_id,
          reason: reason === 'duplicate' || reason === 'fraudulent' ? reason : undefined,
        },
        // One Stripe refund per order, ever — a retried/duplicate client
        // request for the same order_id returns the original refund
        // instead of creating a second one.
        { idempotencyKey: `refund_${order_id}` },
      );
    } catch (stripeErr) {
      return jsonError(`Stripe refund failed: ${stripeErr}`, 502);
    }

    const { error: updateError } = await admin
      .from('orders')
      .update({
        status: 'refunded',
        stripe_refund_id: refund.id,
        refund_amount: refund.amount / 100,
        refunded_at: new Date().toISOString(),
      })
      .eq('id', order_id)
      .in('status', Array.from(REFUNDABLE_STATUSES));

    if (updateError) {
      // Money has already moved on Stripe's side at this point — surface
      // the refund id so the admin isn't left guessing whether it went
      // through, even though the DB write itself failed.
      return jsonError(
        `Refund was issued on Stripe (${refund.id}) but updating the order failed: ${updateError.message}`,
        500,
      );
    }

    await notifyOrderStatus(order_id, 'refunded');

    return new Response(
      JSON.stringify({ refundId: refund.id, amount: refund.amount / 100 }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});
