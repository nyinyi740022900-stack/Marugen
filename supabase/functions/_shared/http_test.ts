import { escapeHtml, fetchWithTimeout, isTimeoutError } from "./http.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
Deno.test("fetchWithTimeout aborts a call that never answers and reports a timeout", async () => {
  const original = globalThis.fetch;
  // A provider that accepts the connection and then says nothing.
  globalThis.fetch = ((_input: unknown, init?: RequestInit) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener(
        "abort",
        () => reject(init.signal!.reason),
      );
    })) as typeof fetch;
  try {
    const started = Date.now();
    let caught: unknown;
    try {
      await fetchWithTimeout("https://example.invalid", { method: "POST" }, 30);
    } catch (error) {
      caught = error;
    }
    assert(caught, "a silent provider must not be awaited forever");
    assert(isTimeoutError(caught), "the failure must be recognisable");
    assert(Date.now() - started < 2000, "the budget was not applied");
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("fetchWithTimeout passes the request through and keeps a fast answer", async () => {
  const original = globalThis.fetch;
  let seen: RequestInit | undefined;
  globalThis.fetch = ((_input: unknown, init?: RequestInit) => {
    seen = init;
    return Promise.resolve(new Response("ok"));
  }) as typeof fetch;
  try {
    const response = await fetchWithTimeout("https://example.invalid", {
      method: "POST",
      body: "x",
    }, 5000);
    assert(await response.text() === "ok", "response lost");
    assert(
      seen?.method === "POST" && seen.body === "x" && seen.signal,
      "request options or signal missing",
    );
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("an ordinary failure is not mistaken for a timeout", () => {
  assert(!isTimeoutError(new Error("connection refused")), "wrong class");
  assert(!isTimeoutError(null), "null");
});
Deno.test("escapeHtml neutralises markup from a query string", () => {
  const out = escapeHtml(`<script>alert("x")</script>&'\``);
  assert(
    out ===
      "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;&#39;&#96;",
    out,
  );
  assert(escapeHtml("access_denied") === "access_denied", "plain text changed");
});
