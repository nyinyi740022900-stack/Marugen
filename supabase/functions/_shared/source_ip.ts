// Diagnostic for webhooks that filter on the caller's IP address. It reports
// which forwarding headers the platform sets and where an allowlisted address
// sits in them. It decides nothing: the caller keeps its own allowlist rule.
//
// Only IP addresses are ever returned. Any other header content is replaced
// by "(not-an-ip)", and Authorization, cookies and the body are never read.

// Headers that carry the client address on the platforms in front of an Edge
// Function (Cloudflare, Deno Deploy, Envoy, Fastly, generic proxies).
const SINGLE_IP_HEADERS = [
  "x-real-ip",
  "cf-connecting-ip",
  "cf-connecting-ipv6",
  "true-client-ip",
  "x-client-ip",
  "x-cluster-client-ip",
  "fastly-client-ip",
  "fly-client-ip",
  "x-envoy-external-address",
  "x-original-forwarded-for",
];
const MAX_ENTRIES = 12;

/** The value if it is an IP address, otherwise a fixed placeholder. */
export function ipOnly(value: string): string {
  const v = value.trim().replace(/^\[|\]$/g, "");
  const v4 = /^(\d{1,3})(\.\d{1,3}){3}$/.test(v) &&
    v.split(".").every((part) => Number(part) <= 255);
  const v6 = v.length <= 45 && v.includes(":") && /^[0-9a-f:.]+$/i.test(v);
  return v4 || v6 ? v.toLowerCase() : "(not-an-ip)";
}
function chain(value: string | null): string[] {
  return value ? value.split(",").slice(0, MAX_ENTRIES).map(ipOnly) : [];
}

export type SourceIpDiagnostic = {
  /** x-forwarded-for, left (index 0) to right, IPs only. */
  x_forwarded_for: string[];
  /** Other client-address headers that are present, IPs only. */
  headers: Record<string, string[]>;
  /** Names (never values) of any other header that looks address related. */
  other_header_names: string[];
  /** Every place an allowlisted address was found. */
  allowlisted_at: {
    header: string;
    index: number;
    /** 1 = last entry (added by the hop nearest the function), 2 = the one before. */
    from_end: number;
    ip: string;
  }[];
};

export function sourceIpDiagnostic(
  headers: Headers,
  allowed: ReadonlySet<string>,
): SourceIpDiagnostic {
  const forwarded = chain(headers.get("x-forwarded-for"));
  const present: Record<string, string[]> = {};
  for (const name of SINGLE_IP_HEADERS) {
    const values = chain(headers.get(name));
    if (values.length) present[name] = values;
  }
  const known = new Set(["x-forwarded-for", ...SINGLE_IP_HEADERS]);
  const others: string[] = [];
  headers.forEach((_value, name) => {
    const n = name.toLowerCase();
    if (
      !known.has(n) && others.length < MAX_ENTRIES &&
      /(^|-)ip(v6)?$|forwarded|client-ip|connecting|-addr(ess)?$|^via$/.test(n)
    ) others.push(n.slice(0, 60));
  });
  const allowlistedAt: SourceIpDiagnostic["allowlisted_at"] = [];
  const scan = (header: string, values: string[]) =>
    values.forEach((ip, index) => {
      if (allowed.has(ip)) {
        allowlistedAt.push({
          header,
          index,
          from_end: values.length - index,
          ip,
        });
      }
    });
  scan("x-forwarded-for", forwarded);
  for (const [name, values] of Object.entries(present)) scan(name, values);
  return {
    x_forwarded_for: forwarded,
    headers: present,
    other_header_names: others.sort(),
    allowlisted_at: allowlistedAt,
  };
}
