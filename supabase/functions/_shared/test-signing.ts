// Test-only: builds an Apple-shaped certificate chain (root → intermediate → leaf)
// with throwaway keys and signs JWS with it, so the verifier and the functions can
// be tested without real App Store data. Never imported by function code.

const enc = new TextEncoder();

function len(n: number): number[] {
  if (n < 0x80) return [n];
  const out: number[] = [];
  while (n > 0) {
    out.unshift(n & 0xff);
    n >>= 8;
  }
  return [0x80 | out.length, ...out];
}

function tlv(tag: number, ...parts: Uint8Array[]): Uint8Array {
  const body = concat(...parts);
  return concat(new Uint8Array([tag, ...len(body.length)]), body);
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

function oid(dotted: string): Uint8Array {
  const [a, b, ...rest] = dotted.split(".").map(Number);
  const out = [a * 40 + b];
  for (const v of rest) {
    const chunk = [v & 0x7f];
    let x = Math.floor(v / 128);
    while (x > 0) {
      chunk.unshift((x & 0x7f) | 0x80);
      x = Math.floor(x / 128);
    }
    out.push(...chunk);
  }
  return tlv(0x06, new Uint8Array(out));
}

const seq = (...p: Uint8Array[]) => tlv(0x30, ...p);
const int = (v: number) => tlv(0x02, new Uint8Array([v]));
const name = (cn: string) => seq(tlv(0x31, seq(oid("2.5.4.3"), tlv(0x0c, enc.encode(cn)))));
const time = (d: Date) => tlv(0x18, enc.encode(d.toISOString().replace(/[-:T]/g, "").slice(0, 14) + "Z"));

function rawToDer(raw: Uint8Array): Uint8Array {
  const half = raw.length / 2;
  const integer = (b: Uint8Array) => {
    let i = 0;
    while (i < b.length - 1 && b[i] === 0) i++;
    const v = b.subarray(i);
    return tlv(0x02, v[0] & 0x80 ? concat(new Uint8Array([0]), v) : v);
  };
  return seq(integer(raw.subarray(0, half)), integer(raw.subarray(half)));
}

export interface Signer {
  cert: Uint8Array;
  keys: CryptoKeyPair;
  curve: "P-256" | "P-384";
  cn: string;
}

async function makeCert(opts: {
  cn: string;
  curve: "P-256" | "P-384";
  issuer?: Signer;
  extensionOid?: string;
  notBefore?: Date;
  notAfter?: Date;
}): Promise<Signer> {
  const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: opts.curve }, true, ["sign", "verify"]) as CryptoKeyPair;
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", keys.publicKey));
  const signerKey = opts.issuer?.keys.privateKey ?? keys.privateKey;
  const signerCurve = opts.issuer?.curve ?? opts.curve;
  const hash = signerCurve === "P-384" ? "SHA-384" : "SHA-256";
  const sigAlg = seq(oid(hash === "SHA-384" ? "1.2.840.10045.4.3.3" : "1.2.840.10045.4.3.2"));
  const extensions = opts.extensionOid
    ? [tlv(0xa3, seq(seq(oid(opts.extensionOid), tlv(0x04, tlv(0x05)))))]
    : [];
  const tbs = seq(
    tlv(0xa0, int(2)),
    int(1),
    sigAlg,
    name(opts.issuer?.cn ?? opts.cn),
    seq(time(opts.notBefore ?? new Date("2020-01-01T00:00:00Z")), time(opts.notAfter ?? new Date("2040-01-01T00:00:00Z"))),
    name(opts.cn),
    spki,
    ...extensions,
  );
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash }, signerKey, tbs));
  const cert = seq(tbs, sigAlg, tlv(0x03, concat(new Uint8Array([0]), rawToDer(raw))));
  return { cert, keys, curve: opts.curve, cn: opts.cn };
}

export interface TestChain {
  root: Signer;
  intermediate: Signer;
  leaf: Signer;
  rootSha256: string;
}

export async function makeChain(leafOptions: { notAfter?: Date; leafOid?: string } = {}): Promise<TestChain> {
  const root = await makeCert({ cn: "Test Root", curve: "P-384" });
  const intermediate = await makeCert({ cn: "Test WWDR", curve: "P-384", issuer: root, extensionOid: "1.2.840.113635.100.6.2.1" });
  const leaf = await makeCert({
    cn: "Test Signing",
    curve: "P-256",
    issuer: intermediate,
    extensionOid: leafOptions.leafOid ?? "1.2.840.113635.100.6.11.1",
    notAfter: leafOptions.notAfter,
  });
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", root.cert));
  return { root, intermediate, leaf, rootSha256: Array.from(digest, (v) => v.toString(16).padStart(2, "0")).join("") };
}

const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
const b64url = (b: Uint8Array) => b64(b).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

export async function signJWS(chain: TestChain, payload: unknown, signWith: Signer = chain.leaf): Promise<string> {
  const header = b64url(enc.encode(JSON.stringify({ alg: "ES256", x5c: [chain.leaf, chain.intermediate, chain.root].map((s) => b64(s.cert)) })));
  const body = b64url(enc.encode(JSON.stringify(payload)));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signWith.keys.privateKey, enc.encode(`${header}.${body}`)));
  return `${header}.${body}.${b64url(sig)}`;
}
