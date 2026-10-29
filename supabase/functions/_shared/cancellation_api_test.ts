import { createCancellationHandler } from "./cancellation_api.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
function fixture() {
  const actions: any[] = [];
  const handler = createCancellationHandler({
    authenticate: async (token) => token === "Bearer valid" ? "actor" : null,
    execute: async (...args) => {
      actions.push(args);
      return {
        request: { order_id: args[0], user_id: "u", status: "requested" },
        changed: true,
      };
    },
  });
  const send = (body: unknown, token = "Bearer valid", method = "POST") =>
    handler(
      new Request("https://example.invalid", {
        method,
        headers: { Authorization: token, "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }),
    );
  return { actions, send };
}
Deno.test("cancellation HTTP rejects unauthenticated and invalid actions before mutation", async () => {
  const f = fixture();
  assert(
    (await f.send({ order_id: "x", action: "approve" }, "Bearer wrong"))
      .status === 401,
    "auth required",
  );
  assert(
    (await f.send({
      order_id: "c6610000-0000-0000-0000-000000000001",
      action: "cancel",
    })).status === 400,
    "invalid action",
  );
  assert(f.actions.length === 0, "invalid request mutated state");
});
Deno.test("optional customer reason gets safe default and actor comes from verified token", async () => {
  const f = fixture();
  const response = await f.send({
    order_id: "c6610000-0000-0000-0000-000000000001",
    action: "request",
    actor_id: "forged",
  });
  assert(response.status === 200, "request rejected");
  assert(
    f.actions[0][1] === "actor" &&
      f.actions[0][3] === "Customer requested cancellation",
    "untrusted actor or empty reason",
  );
});
Deno.test("cancellation errors preserve forbidden status and malformed JSON is rejected", async () => {
  const handler = createCancellationHandler({
    authenticate: async () => "actor",
    execute: async () => {
      throw { code: "42501", message: "Cancellation access denied" };
    },
  });
  const response = await handler(
    new Request("https://example.invalid", {
      method: "POST",
      headers: { Authorization: "Bearer valid" },
      body: JSON.stringify({
        order_id: "c6610000-0000-0000-0000-000000000001",
        action: "approve",
      }),
    }),
  );
  assert(response.status === 403, "forbidden must remain forbidden");
  const malformed = await handler(
    new Request("https://example.invalid", {
      method: "POST",
      headers: { Authorization: "Bearer valid" },
      body: "{",
    }),
  );
  assert(malformed.status === 400, "malformed JSON must be bad request");
});
