import {
  type RefundPort,
  type RefundResult,
  requestOrderRefund,
} from "./refund_lifecycle.ts";
export type CancellationRequest = {
  order_id: string;
  user_id: string | null;
  status: string;
  [key: string]: unknown;
};
export type CancellationAction = "request" | "approve" | "reject" | "refresh";
export type CancellationPort = {
  port: RefundPort;
  transition: (
    orderId: string,
    actorId: string,
    action: CancellationAction,
    reason?: string,
  ) => Promise<{ request: CancellationRequest; changed: boolean }>;
};
export async function handleCancellation(
  orderId: string,
  actorId: string,
  action: CancellationAction,
  reason: string | undefined,
  port: CancellationPort,
): Promise<
  {
    request: CancellationRequest;
    refund?: RefundResult;
    refund_error?: string;
    changed: boolean;
  }
> {
  const result = await port.transition(orderId, actorId, action, reason);
  if (action !== "approve" && action !== "refresh") return result;
  if (result.request.status !== "approved") {
    throw new Error("Cancellation must be approved before refunding");
  }
  try {
    const refund = await requestOrderRefund(
      orderId,
      undefined,
      port.port,
      action === "refresh",
    );
    return { ...result, refund };
  } catch (error) {
    // The approval and fulfillment hold already committed. Keep them while staff
    // reconcile Stripe; retrying approval uses the shared verified refund flow.
    return {
      ...result,
      refund_error: error instanceof Error ? error.message : String(error),
    };
  }
}
