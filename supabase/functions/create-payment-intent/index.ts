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
  size_label?: string | null;
};

type BuiltLine = {
  product_id: string;
  product_name: string;
  quantity: number;
  unit_price: number;
  variant_id?: string;
  variant_label?: string;
  size_label?: string;
  image_url?: string | null;
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
    // Prefer the new publishable/secret key pair (set explicitly via
    // `supabase secrets set`) over the legacy JWT anon/service_role names
    // auto-injected by the platform, so this keeps working whether or not
    // legacy JWT-based API keys are later disabled project-wide.
    const anonKey = Deno.env.get('SB_ANON_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceKey =
      Deno.env.get('SB_SERVICE_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

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
    const shippingIn = body.shipping_address as Record<string, unknown> | undefined;
    const promoCodeRaw = (body.promo_code as string | undefined)?.trim();
    const idempotencyKey = (body.idempotency_key as string | undefined)?.trim() || null;

    if (!Array.isArray(itemsIn) || itemsIn.length === 0) {
      return jsonResponse({ error: 'Cart is empty' }, 400);
    }

    // Client sends the same idempotency_key for every retry of one checkout
    // attempt (see checkout_screen.dart). If an earlier call already got as
    // far as creating a pending order + PaymentIntent for this exact key —
    // whether this request is a genuine retry after a dropped response, or
    // it's racing a concurrent one — return that instead of reserving stock
    // and creating a Stripe PaymentIntent a second time.
    const userId: string = user.id;
    async function findExistingPendingOrder() {
      if (!idempotencyKey) return null;
      const { data: existing } = await admin
        .from('orders')
        .select('id, stripe_payment_intent_id, total')
        .eq('user_id', userId)
        .eq('idempotency_key', idempotencyKey)
        .eq('status', 'pending')
        .maybeSingle();
      if (!existing?.stripe_payment_intent_id) return null;
      const existingIntent = await stripe.paymentIntents.retrieve(
        existing.stripe_payment_intent_id,
      );
      return jsonResponse({
        clientSecret: existingIntent.client_secret,
        paymentIntentId: existingIntent.id,
        orderId: existing.id,
        amount: existing.total,
        amountCents: existingIntent.amount,
        currency: existingIntent.currency,
      });
    }

    const existingResponse = await findExistingPendingOrder();
    if (existingResponse) return existingResponse;

    // Delivery-only: the shop hand-delivers every order (see
    // delivery_repository.dart for how live fish are routed to
    // self-delivery instead of a courier). There is no self-collection/
    // pickup flow anymore.
    if (!shippingIn) {
      return jsonResponse({ error: 'Shipping address required' }, 400);
    }
    const shippingAddress: Record<string, unknown> = { ...shippingIn };

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
        .select(
          'id, name, category, price, sale_price, show_price, stock_quantity, is_sold, size_options, image_urls',
        )
        .eq('id', productId)
        .maybeSingle();

      if (productError || !product) {
        return jsonResponse({ error: `Product not found: ${productId}` }, 400);
      }

      const isLiveFish = product.category === 'koi' || product.category === 'arowana';
      // Snapshot the product's cover photo onto the order line — the
      // product itself (and its images) can be edited or deleted later,
      // but the order's item photo should stay as it was at purchase time.
      const imageUrl: string | null =
        Array.isArray(product.image_urls) && product.image_urls.length > 0
          ? product.image_urls[0]
          : null;
      const sizeOptions: string[] = Array.isArray(product.size_options)
        ? product.size_options.filter((s: unknown) => typeof s === 'string' && s.trim().length > 0)
        : [];
      const sizeLabelRaw =
        typeof line.size_label === 'string' ? line.size_label.trim() : '';
      let sizeLabel: string | undefined;
      if (!isLiveFish && sizeOptions.length > 0) {
        if (!sizeLabelRaw || !sizeOptions.includes(sizeLabelRaw)) {
          return jsonResponse(
            { error: `${product.name} requires a valid size` },
            400,
          );
        }
        sizeLabel = sizeLabelRaw;
      } else if (sizeLabelRaw) {
        // Ignore stale client size when the product no longer has sizes.
        sizeLabel = undefined;
      }

      if (line.variant_id) {
        // A live-fish batch listing (e.g. "Japan Imported Koi Selection")
        // uses variants as individual fish/variety picks — each is still
        // one specific animal, so quantity must be 1 just like the
        // no-variant live-fish path below.
        if (isLiveFish && qty !== 1) {
          return jsonResponse({ error: 'Live fish quantity must be 1' }, 400);
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

        if (sizeLabel) {
          const { data: sizeStock, error: sizeStockError } = await admin
            .from('product_variant_size_stocks')
            .select('stock_quantity')
            .eq('variant_id', variant.id)
            .eq('size_label', sizeLabel)
            .maybeSingle();
          if (sizeStockError) {
            return jsonResponse({ error: 'Could not check size stock' }, 500);
          }
          const available = Number(sizeStock?.stock_quantity ?? 0);
          if (available < qty) {
            return jsonResponse(
              {
                error: `${product.name} (${variant.label} · ${sizeLabel}) is out of stock`,
              },
              400,
            );
          }
        } else if (variant.stock_quantity < qty) {
          return jsonResponse(
            { error: `${product.name} (${variant.label}) is out of stock` },
            400,
          );
        }

        const unit = Number(variant.price);
        builtLines.push({
          product_id: product.id,
          product_name: product.name,
          quantity: qty,
          unit_price: unit,
          variant_id: variant.id,
          variant_label: variant.label,
          size_label: sizeLabel,
          image_url: imageUrl,
        });
        subtotal += unit * qty;
      } else {
        if (!product.show_price || product.price == null) {
          return jsonResponse({ error: `${product.name} is contact-for-price` }, 400);
        }
        // Variant products (weight options, or a live-fish batch listing's
        // fish/variety picks) must choose one on the client — checked
        // before the base price/stock fields below, which are unused once
        // variants exist and may be stale.
        const { count } = await admin
          .from('product_variants')
          .select('id', { count: 'exact', head: true })
          .eq('product_id', productId);
        if ((count ?? 0) > 0) {
          return jsonResponse({ error: `${product.name} requires a variant` }, 400);
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

        // Sale price wins only when it's actually a discount — never
        // trust it blindly (e.g. a stale/bad value >= price).
        const salePrice = Number(product.sale_price);
        const unit =
          product.sale_price != null && salePrice < Number(product.price)
            ? salePrice
            : Number(product.price);
        builtLines.push({
          product_id: product.id,
          product_name: product.name,
          quantity: qty,
          unit_price: unit,
          size_label: sizeLabel,
          image_url: imageUrl,
        });
        subtotal += unit * qty;
      }
    }

    subtotal = roundMoney(subtotal);

    let discountAmount = 0;
    let promoCode: string | null = null;
    let promoId: string | null = null;
    if (promoCodeRaw) {
      const { data: promo } = await admin
        .from('promo_codes')
        .select(
          'id, code, discount_type, discount_value, active, expires_at, max_redemptions, times_redeemed',
        )
        .ilike('code', promoCodeRaw)
        .maybeSingle();

      if (!promo || !promo.active) {
        return jsonResponse({ error: 'Invalid promo code' }, 400);
      }
      if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
        return jsonResponse({ error: 'Promo code expired' }, 400);
      }
      if (promo.max_redemptions != null && promo.times_redeemed >= promo.max_redemptions) {
        return jsonResponse({ error: 'This promo code has reached its usage limit' }, 400);
      }
      const { data: alreadyUsed } = await admin
        .from('promo_code_redemptions')
        .select('id')
        .eq('promo_code_id', promo.id)
        .eq('user_id', user.id)
        .maybeSingle();
      if (alreadyUsed) {
        return jsonResponse({ error: 'You have already used this promo code' }, 400);
      }

      const raw =
        promo.discount_type === 'percent'
          ? subtotal * Number(promo.discount_value) / 100
          : Number(promo.discount_value);
      discountAmount = roundMoney(Math.min(Math.max(raw, 0), subtotal));
      promoCode = promo.code;
      promoId = promo.id;
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
        idempotency_key: idempotencyKey,
      })
      .select('id')
      .single();

    if (orderError || !order) {
      // 23505 = unique_violation on orders_user_pending_idempotency_key_uidx
      // — a concurrent request with the same idempotency_key won the race
      // and inserted its pending order first. Return that one instead of
      // failing the request outright.
      if (orderError?.code === '23505') {
        const raced = await findExistingPendingOrder();
        if (raced) return raced;
      }
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
        size_label: line.size_label ?? null,
        image_url: line.image_url ?? null,
      })),
    );

    if (itemsError) {
      await admin.from('orders').update({ status: 'cancelled' }).eq('id', orderId);
      return jsonResponse({ error: itemsError.message || 'Stock unavailable' }, 409);
    }

    // Claim the promo code atomically, the same way live-fish stock is
    // claimed above (0010_payment_integrity.sql) — a plain check-then-use
    // here would let two concurrent checkouts both slip past the cap or
    // both redeem as the same user. `claim_promo_redemption` does the
    // capped increment as one server-side statement; the redemption
    // INSERT can only succeed once per (promo_code_id, user_id) thanks to
    // the unique constraint in 0015_promo_code_limits.sql. Cancelling the
    // order on failure re-runs the same stock-restore trigger the
    // itemsError/stripeErr paths rely on, so nothing is left half-reserved.
    if (promoId) {
      const { data: claimed, error: claimError } = await admin.rpc('claim_promo_redemption', {
        p_promo_id: promoId,
      });
      if (claimError || !claimed) {
        await admin.from('orders').update({ status: 'cancelled' }).eq('id', orderId);
        return jsonResponse({ error: 'This promo code has reached its usage limit' }, 409);
      }

      const { error: redemptionError } = await admin.from('promo_code_redemptions').insert({
        promo_code_id: promoId,
        user_id: user.id,
        order_id: orderId,
      });
      if (redemptionError) {
        // Unique violation (promo_code_id, user_id) means this user
        // already redeemed it — release the slot we just claimed above so
        // the cap isn't wrongly consumed by a rejected attempt.
        await admin.rpc('release_promo_redemption', { p_promo_id: promoId });
        await admin.from('orders').update({ status: 'cancelled' }).eq('id', orderId);
        return jsonResponse({ error: 'You have already used this promo code' }, 409);
      }
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
