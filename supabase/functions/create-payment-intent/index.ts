// Supabase Edge Function: create-payment-intent
//
// Validates cart against DB prices/stock, creates a pending order (stock
// reserved via order_items trigger), then creates a Stripe PaymentIntent for
// the *server-calculated* total. Client-sent amounts are ignored.
//
// Deploy:   supabase functions deploy create-payment-intent
// Secrets:  supabase secrets set STRIPE_SECRET_KEY=sk_test_xxx

import Stripe from 'https://esm.sh/stripe@17?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-06-20',
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

type CartLineIn = {
  product_id: string;
  quantity: number;
  variant_id?: string | null;
};

type BuiltLine = {
  product_id: string;
  product_name: string;
  quantity: number;
  unit_price: number;
  variant_id?: string;
  variant_label?: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function roundMoney(n: number) {
  return Math.round(n * 100) / 100;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return jsonResponse({ error: 'Missing authorization' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(supabaseUrl, serviceKey);

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return jsonResponse({ error: 'Unauthorized' }, 401);
    }

    const body = await req.json();
    const itemsIn = (body.items ?? []) as CartLineIn[];
    const currency = (body.currency as string | undefined) ?? 'sgd';
    const fulfillment = body.fulfillment === 'pickup' ? 'pickup' : 'delivery';
    const shippingIn = body.shipping_address as Record<string, unknown> | undefined;
    const promoCodeRaw = (body.promo_code as string | undefined)?.trim();

    if (!Array.isArray(itemsIn) || itemsIn.length === 0) {
      return jsonResponse({ error: 'Cart is empty' }, 400);
    }

    let shippingAddress: Record<string, unknown>;
    if (fulfillment === 'pickup') {
      const { data: settings } = await admin
        .from('settings')
        .select('shop_name, shop_phone, shop_address')
        .eq('id', 1)
        .maybeSingle();
      shippingAddress = {
        fulfillment: 'pickup',
        label: 'Self-collection',
        recipient_name: settings?.shop_name ?? 'Marugen Koi Farm',
        phone: settings?.shop_phone ?? '',
        line1: settings?.shop_address ?? 'Farm pickup',
        city: 'Singapore',
        postal_code: '',
      };
    } else {
      if (!shippingIn) {
        return jsonResponse({ error: 'Shipping address required' }, 400);
      }
      shippingAddress = { ...shippingIn, fulfillment: 'delivery' };
    }

    const builtLines: BuiltLine[] = [];
    let subtotal = 0;

    for (const line of itemsIn) {
      const productId = line.product_id;
      const qty = Math.floor(Number(line.quantity) || 0);
      if (!productId || qty < 1) {
        return jsonResponse({ error: 'Invalid cart line' }, 400);
      }

      const { data: product, error: productError } = await admin
        .from('products')
        .select('id, name, category, price, show_price, stock_quantity, is_sold')
        .eq('id', productId)
        .maybeSingle();

      if (productError || !product) {
        return jsonResponse({ error: `Product not found: ${productId}` }, 400);
      }

      const isLiveFish = product.category === 'koi' || product.category === 'arowana';

      if (line.variant_id) {
        if (isLiveFish) {
          return jsonResponse({ error: 'Live fish cannot have variants' }, 400);
        }

        const { data: variant, error: variantError } = await admin
          .from('product_variants')
          .select('id, product_id, label, price, stock_quantity')
          .eq('id', line.variant_id)
          .eq('product_id', productId)
          .maybeSingle();

        if (variantError || !variant) {
          return jsonResponse({ error: `Variant not found: ${line.variant_id}` }, 400);
        }
        if (!product.show_price) {
          return jsonResponse({ error: `${product.name} is contact-for-price` }, 400);
        }
        if (variant.stock_quantity < qty) {
          return jsonResponse({ error: `${product.name} (${variant.label}) is out of stock` }, 400);
        }

        const unit = Number(variant.price);
        builtLines.push({
          product_id: product.id,
          product_name: product.name,
          quantity: qty,
          unit_price: unit,
          variant_id: variant.id,
          variant_label: variant.label,
        });
        subtotal += unit * qty;
      } else {
        if (!product.show_price || product.price == null) {
          return jsonResponse({ error: `${product.name} is contact-for-price` }, 400);
        }
        if (isLiveFish) {
          if (qty !== 1) {
            return jsonResponse({ error: 'Live fish quantity must be 1' }, 400);
          }
          if (product.is_sold || product.stock_quantity < 1) {
            return jsonResponse({ error: `${product.name} is already sold` }, 400);
          }
        } else if (product.stock_quantity < qty) {
          return jsonResponse({ error: `${product.name} is out of stock` }, 400);
        }

        // Variant products must pick a size on the client.
        const { count } = await admin
          .from('product_variants')
          .select('id', { count: 'exact', head: true })
          .eq('product_id', productId);
        if (!isLiveFish && (count ?? 0) > 0) {
          return jsonResponse({ error: `${product.name} requires a variant` }, 400);
        }

        const unit = Number(product.price);
        builtLines.push({
          product_id: product.id,
          product_name: product.name,
          quantity: qty,
          unit_price: unit,
        });
        subtotal += unit * qty;
      }
    }

    subtotal = roundMoney(subtotal);

    let discountAmount = 0;
    let promoCode: string | null = null;
    if (promoCodeRaw) {
      const { data: promo } = await admin
        .from('promo_codes')
        .select('code, discount_type, discount_value, active, expires_at')
        .ilike('code', promoCodeRaw)
        .maybeSingle();

      if (!promo || !promo.active) {
        return jsonResponse({ error: 'Invalid promo code' }, 400);
      }
      if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
        return jsonResponse({ error: 'Promo code expired' }, 400);
      }

      const raw =
        promo.discount_type === 'percent'
          ? subtotal * Number(promo.discount_value) / 100
          : Number(promo.discount_value);
      discountAmount = roundMoney(Math.min(Math.max(raw, 0), subtotal));
      promoCode = promo.code;
    }

    const netSubtotal = roundMoney(subtotal - discountAmount);

    const { data: settings } = await admin
      .from('settings')
      .select('gst_percent, gst_included_in_price')
      .eq('id', 1)
      .maybeSingle();

    const gstPercent = Number(settings?.gst_percent ?? 9);
    const gstIncluded = settings?.gst_included_in_price !== false;

    let payableTotal = netSubtotal;
    if (!gstIncluded && gstPercent > 0) {
      payableTotal = roundMoney(netSubtotal + netSubtotal * gstPercent / 100);
    }

    if (payableTotal <= 0) {
      return jsonResponse({ error: 'Invalid total' }, 400);
    }

    const amountCents = Math.round(payableTotal * 100);

    const { data: order, error: orderError } = await admin
      .from('orders')
      .insert({
        user_id: user.id,
        status: 'pending',
        total: payableTotal,
        shipping_address: shippingAddress,
        promo_code: promoCode,
        discount_amount: discountAmount > 0 ? discountAmount : null,
      })
      .select('id')
      .single();

    if (orderError || !order) {
      return jsonResponse({ error: `Could not create order: ${orderError?.message}` }, 500);
    }

    const orderId = order.id as string;

    const { error: itemsError } = await admin.from('order_items').insert(
      builtLines.map((line) => ({
        order_id: orderId,
        product_id: line.product_id,
        product_name: line.product_name,
        quantity: line.quantity,
        unit_price: line.unit_price,
        variant_id: line.variant_id ?? null,
        variant_label: line.variant_label ?? null,
      })),
    );

    if (itemsError) {
      await admin.from('orders').update({ status: 'cancelled' }).eq('id', orderId);
      return jsonResponse({ error: itemsError.message || 'Stock unavailable' }, 409);
    }

    let paymentIntent: Stripe.PaymentIntent;
    try {
      paymentIntent = await stripe.paymentIntents.create({
        amount: amountCents,
        currency,
        automatic_payment_methods: { enabled: true },
        metadata: {
          order_id: orderId,
          user_id: user.id,
        },
      });
    } catch (stripeErr) {
      await admin.from('orders').update({ status: 'cancelled' }).eq('id', orderId);
      return jsonResponse({ error: `Stripe error: ${stripeErr}` }, 500);
    }

    const { error: linkError } = await admin
      .from('orders')
      .update({ stripe_payment_intent_id: paymentIntent.id })
      .eq('id', orderId);

    if (linkError) {
      await stripe.paymentIntents.cancel(paymentIntent.id).catch(() => {});
      await admin.from('orders').update({ status: 'cancelled' }).eq('id', orderId);
      return jsonResponse({ error: `Could not link payment: ${linkError.message}` }, 500);
    }

    return jsonResponse({
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
      orderId,
      amount: payableTotal,
      amountCents,
      currency,
    });
  } catch (err) {
    return jsonResponse({ error: `${err}` }, 500);
  }
});
