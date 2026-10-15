import Stripe from "https://esm.sh/stripe@17?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cancelPendingPayment } from "../_shared/payment_lifecycle.ts";
import { createPaymentPort } from "../_shared/payment_port.ts";
const url = Deno.env.get("SUPABASE_URL") ?? "";
const anon = Deno.env.get("SB_ANON_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ??
  "";
const key = Deno.env.get("SB_SERVICE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(url, key);
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-06-20",
});
const port = createPaymentPort(admin, stripe, url, key);
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization,apikey,content-type,x-client-info",
};
function reply(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return reply({});
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization) return reply({ error: "Unauthorized" }, 401);
  try {
    const client = createClient(url, anon, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user }, error } = await client.auth.getUser();
    if (error || !user) return reply({ error: "Unauthorized" }, 401);
    const body = await req.json();
    if (typeof body.order_id !== "string") {
      return reply({ error: "Order id required" }, 400);
    }
    const order = await port.getOrder(body.order_id);
    if (!order) return reply({ error: "Order not found" }, 404);
    if (order.user_id !== user.id) {
      const { data: profile } = await admin.from("profiles").select("role").eq(
        "id",
        user.id,
      ).maybeSingle();
      if (!profile || !["staff", "owner"].includes(profile.role)) {
        return reply({ error: "Order not found" }, 404);
      }
    }
    await cancelPendingPayment(order.id, port);
    return reply({ cancelled: true });
  } catch (error) {
    console.error("Order cancellation failed", error);
    return reply({
      error:
        "Cancellation could not be confirmed. Refresh the order; if payment completed, contact the shop for a refund.",
    }, 409);
  }
});
