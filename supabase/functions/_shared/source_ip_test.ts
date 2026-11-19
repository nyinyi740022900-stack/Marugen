import { sourceIpDiagnostic } from "./source_ip.ts";
function assert(v: unknown, m: string) {
  if (!v) throw new Error(m);
}
const ALLOWED = new Set(["47.254.255.46", "117.53.155.92"]);
Deno.test("reports the whole chain and where the allowlisted address sits", () => {
  const d = sourceIpDiagnostic(
    new Headers({
      "x-forwarded-for": "47.254.255.46, 172.70.1.9,10.0.0.7",
      "x-real-ip": "172.70.1.9",
      "cf-connecting-ip": "47.254.255.46",
    }),
    ALLOWED,
  );
  assert(
    JSON.stringify(d.x_forwarded_for) ===
      JSON.stringify(["47.254.255.46", "172.70.1.9", "10.0.0.7"]),
    "chain",
  );
  assert(
    JSON.stringify(d.allowlisted_at) === JSON.stringify([
      { header: "x-forwarded-for", index: 0, from_end: 3, ip: "47.254.255.46" },
      {
        header: "cf-connecting-ip",
        index: 0,
        from_end: 1,
        ip: "47.254.255.46",
      },
    ]),
    `matches: ${JSON.stringify(d.allowlisted_at)}`,
  );
  assert(d.headers["x-real-ip"][0] === "172.70.1.9", "x-real-ip");
});
Deno.test("a spoofed first entry is visible as such", () => {
  // The caller sent the allowlisted address; the proxy appended the real peer.
  const d = sourceIpDiagnostic(
    new Headers({ "x-forwarded-for": "117.53.155.92, 203.0.113.50" }),
    ALLOWED,
  );
  assert(
    d.allowlisted_at.length === 1 && d.allowlisted_at[0].index === 0 &&
      d.allowlisted_at[0].from_end === 2,
    "position",
  );
  const none = sourceIpDiagnostic(
    new Headers({ "x-forwarded-for": "203.0.113.50" }),
    ALLOWED,
  );
  assert(none.allowlisted_at.length === 0, "false match");
});
Deno.test("nothing but IP addresses and header names is ever reported", () => {
  const d = sourceIpDiagnostic(
    new Headers({
      "x-forwarded-for": "Bearer sk_live_abc, 2001:DB8::1, <script>",
      "x-real-ip": "jane@example.com",
      "authorization": "Bearer service-role-secret",
      "cookie": "sb-access-token=secret",
      "x-secret-forwarded-token": "secret-value",
      "content-type": "application/json",
    }),
    ALLOWED,
  );
  const text = JSON.stringify(d);
  assert(
    !/sk_live|service-role|secret-value|sb-access|jane@|script/.test(text),
    `leaked: ${text}`,
  );
  assert(
    JSON.stringify(d.x_forwarded_for) ===
      JSON.stringify(["(not-an-ip)", "2001:db8::1", "(not-an-ip)"]),
    "chain was not reduced to IPs",
  );
  // Names only for unknown address-like headers; unrelated headers ignored.
  assert(
    JSON.stringify(d.other_header_names) ===
      JSON.stringify(["x-secret-forwarded-token"]),
    `names: ${d.other_header_names}`,
  );
});
Deno.test("an oversized chain is capped", () => {
  const d = sourceIpDiagnostic(
    new Headers({
      "x-forwarded-for": Array.from({ length: 500 }, () => "1.2.3.4").join(","),
    }),
    ALLOWED,
  );
  assert(d.x_forwarded_for.length === 12, "not capped");
});
