// Supabase Edge Function: delete-account
//
// Lets a signed-in customer request deletion of their own account, called
// from the "Delete my account" option in profile_screen.dart. Required by
// Google Play's Account Deletion policy (any app that lets users create an
// account must offer a way to delete it) and by the deletion right promised
// in docs/privacy.html.
//
// A hard delete isn't always possible: `orders.user_id` has no ON DELETE
// cascade (orders are kept for accounting/tax reasons — see privacy.html
// section 5), so deleting auth.users would fail with a foreign-key error
// for anyone who has ever placed an order. Behaviour:
//   - No orders on file  -> hard delete: removes the auth user, which
//     cascades to profiles/addresses/wishlist_items/product_reviews.
//   - Has order history  -> anonymize: wipe personal fields from the
//     profile, delete addresses/wishlist/reviews, then permanently ban
//     the auth user and scramble its email/password so it can never sign
//     in again. Order rows themselves are left untouched.
//
// Deploy:  supabase functions deploy delete-account
// Secrets: none beyond the project's existing SUPABASE_URL / anon / service
//          role keys (same as every other function in this project).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

    const { count: orderCount, error: orderCountError } = await admin
      .from('orders')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id);
    if (orderCountError) {
      return jsonError(`Could not check order history: ${orderCountError.message}`, 500);
    }

    // Always clear what we can delete outright regardless of which path
    // below is taken — none of these are needed for accounting records.
    await admin.from('wishlist_items').delete().eq('user_id', user.id);
    await admin.from('product_reviews').delete().eq('user_id', user.id);
    await admin.from('addresses').delete().eq('user_id', user.id);

    if (!orderCount) {
      // No order history — safe to remove the auth user outright. This
      // cascades to the profiles row (and, transitively, anything with an
      // `on delete cascade` FK to it) automatically.
      const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
      if (deleteError) {
        return jsonError(`Could not delete account: ${deleteError.message}`, 500);
      }
      return new Response(JSON.stringify({ deleted: true, anonymized: false }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Has order history — anonymize instead of hard-deleting so the
    // orders (and their FK to profiles.id) stay intact for accounting/tax
    // purposes, matching docs/privacy.html section 5. The account is
    // permanently banned so it can never be signed back into.
    const { error: profileError } = await admin
      .from('profiles')
      .update({
        full_name: 'Deleted user',
        phone: null,
        avatar_url: null,
        fcm_token: null,
      })
      .eq('id', user.id);
    if (profileError) {
      return jsonError(`Could not anonymize profile: ${profileError.message}`, 500);
    }

    const { error: banError } = await admin.auth.admin.updateUserById(user.id, {
      email: `deleted-${user.id}@deleted.marugen.invalid`,
      password: crypto.randomUUID() + crypto.randomUUID(),
      ban_duration: '876000h', // ~100 years — effectively permanent
      user_metadata: {},
    });
    if (banError) {
      return jsonError(`Could not disable sign-in: ${banError.message}`, 500);
    }

    return new Response(JSON.stringify({ deleted: false, anonymized: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});
