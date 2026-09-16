// Supabase Edge Function: create-payment-intent
//
// Creates a Stripe PaymentIntent for the cart total. Runs server-side so
// the Stripe *secret* key never touches the Flutter app.
//
// Deploy:   supabase functions deploy create-payment-intent
// Secrets:  supabase secrets set STRIPE_SECRET_KEY=sk_test_xxx
//
// Called from the app via:
//   supabase.functions.invoke('create-payment-intent', body: {...})

import Stripe from 'https://esm.sh/stripe@17?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-06-20',
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { amount, currency, items } = await req.json();

    if (!amount || amount <= 0) {
      return new Response(JSON.stringify({ error: 'Invalid amount' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount, // smallest currency unit, e.g. cents
      currency: currency ?? 'sgd',
      automatic_payment_methods: { enabled: true },
      metadata: {
        items: JSON.stringify(items ?? []).slice(0, 500), // Stripe metadata value limit
      },
    });

    return new Response(
      JSON.stringify({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: `${err}` }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
