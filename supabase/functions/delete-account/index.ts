// Requires migration 0051 before deployment. Never bans an account as a deletion substitute.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import { deleteCustomer } from './delete_customer.ts';

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

  if (req.method !== 'POST') return jsonError('Method not allowed', 405);

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

    // Staff accounts may own retained shop images. Route them through support
    // rather than deleting business assets or falsely claiming deletion.
    const { data: profile, error: profileError } = await admin
      .from('profiles').select('role').eq('id', user.id).single();
    if (profileError) return jsonError('Could not verify account. Please contact support.', 500);
    if (profile.role !== 'customer') return jsonError('Staff account deletion requires support: marugenfishfarmaiagent@gmail.com', 409);

    const bucket = admin.storage.from('product-images');
    await deleteCustomer({
      listAvatars: async (prefix, offset) => {
        const { data, error } = await bucket.list(prefix, { limit: 100, offset, sortBy: { column: 'name', order: 'asc' } });
        return { files: (data ?? []).map(f => ({ name: f.name, id: f.id ?? null })), error: error?.message };
      },
      removeAvatars: async paths => {
        const { error } = await bucket.remove(paths);
        return error?.message;
      },
      deleteAuthUser: async id => {
        const { error } = await admin.auth.admin.deleteUser(id);
        return error?.message;
      },
    }, user.id);

    return new Response(JSON.stringify({ deleted: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return jsonError(`${err}`, 500);
  }
});
