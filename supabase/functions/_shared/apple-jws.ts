// Verifies Apple's signed data (JWS) — App Store transactions, renewal info and
// Server Notifications V2 — with Web Crypto only, so it runs in Supabase Edge
// Functions (Deno) and under `node --test`. Apple's own Node library is not used
// because its ES256 check fails in Deno.
//
// A JWS is trusted when:
//   1. its header is ES256 with a three-certificate x5c chain,
//   2. the last certificate is Apple Root CA - G3 (pinned by SHA-256 of its DER),
//   3. each certificate is signed by the next one and valid at the payload's signedDate,
//   4. the leaf and intermediate carry Apple's App Store receipt-signing OIDs,
//   5. the JWS signature verifies with the leaf key.
// Every developer's data chains to the same root, so callers must still check the
// bundle ID and product ID in the payload.

/** SHA-256 of Apple Root CA - G3 (https://www.apple.com/certificateauthority/AppleRootCA-G3.cer). */
export const APPLE_ROOT_CA_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

const OID_LEAF_RECEIPT_SIGNING = "1.2.840.113635.100.6.11.1";
const OID_INTERMEDIATE_WWDR = "1.2.840.113635.100.6.2.1";

export class JwsError extends Error {
  code: string;
  constructor(code: string, message?: string) {
    super(message ?? code);
    this.code = code;
  }
}

export interface VerifyOptions {
  /** Hex SHA-256 fingerprints of accepted roots; tests pass their own. */
  trustedRoots?: string[];
  /** Fallback time for the validity check when the payload has no signedDate. */
  now?: Date;
}

export async function verifyAppleJWS<T = Record<string, unknown>>(jws: string, options: VerifyOptions = {}): Promise<T> {
  const parts = typeof jws === "string" ? jws.split(".") : [];
  if (parts.length !== 3) throw new JwsError("malformed");
  const [headerB64, payloadB64, signatureB64] = parts;

  let header: { alg?: string; x5c?: string[] };
  let payload: T & { signedDate?: number };
  try {
    header = JSON.parse(utf8(base64UrlDecode(headerB64)));
    payload = JSON.parse(utf8(base64UrlDecode(payloadB64)));
  } catch {
    throw new JwsError("malformed");
  }
  if (header.alg !== "ES256") throw new JwsError("unsupported_alg");
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) throw new JwsError("bad_chain");

  const ders = header.x5c.map((c) => base64Decode(c));
  const certs = ders.map(parseCertificate);
  const [leaf, intermediate, root] = certs;

  const roots = options.trustedRoots ?? [APPLE_ROOT_CA_G3_SHA256];
  if (!roots.includes(await sha256Hex(ders[2]))) throw new JwsError("untrusted_root");

  await verifyIssuedBy(intermediate, root);
  await verifyIssuedBy(leaf, intermediate);
  if (!intermediate.extensionOids.includes(OID_INTERMEDIATE_WWDR)) throw new JwsError("bad_chain", "intermediate OID");
  if (!leaf.extensionOids.includes(OID_LEAF_RECEIPT_SIGNING)) throw new JwsError("bad_chain", "leaf OID");

  const signature = base64UrlDecode(signatureB64);
  const leafKey = await importEcKey(leaf);
  const signed = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, leafKey, signature, signed);
  if (!ok) throw new JwsError("bad_signature");

  const at = typeof payload.signedDate === "number" ? new Date(payload.signedDate) : (options.now ?? new Date());
  for (const cert of certs) {
    if (at < cert.notBefore || at > cert.notAfter) throw new JwsError("expired_certificate");
  }
  return payload;
}

// --- X.509 (just enough DER to check an ECDSA chain) ---------------------------

interface Certificate {
  tbs: Uint8Array;
  issuer: Uint8Array;
  subject: Uint8Array;
  spki: Uint8Array;
  curve: "P-256" | "P-384";
  signatureHash: "SHA-256" | "SHA-384";
  signature: Uint8Array; // DER ECDSA-Sig-Value
  notBefore: Date;
  notAfter: Date;
  extensionOids: string[];
}

interface Tlv {
  tag: number;
  start: number;
  contentStart: number;
  end: number;
}

function readTlv(b: Uint8Array, pos: number): Tlv {
  if (pos + 2 > b.length) throw new JwsError("bad_certificate");
  const tag = b[pos];
  let len = b[pos + 1];
  let header = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n < 1 || n > 4) throw new JwsError("bad_certificate");
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + b[pos + 2 + i];
    header += n;
  }
  const end = pos + header + len;
  if (end > b.length) throw new JwsError("bad_certificate");
  return { tag, start: pos, contentStart: pos + header, end };
}

function children(b: Uint8Array, parent: Tlv): Tlv[] {
  const out: Tlv[] = [];
  for (let p = parent.contentStart; p < parent.end;) {
    const child = readTlv(b, p);
    out.push(child);
    p = child.end;
  }
  return out;
}

const bytes = (b: Uint8Array, t: Tlv) => b.subarray(t.start, t.end);
const content = (b: Uint8Array, t: Tlv) => b.subarray(t.contentStart, t.end);

function decodeOid(c: Uint8Array): string {
  const parts = [Math.floor(c[0] / 40), c[0] % 40];
  let value = 0;
  for (let i = 1; i < c.length; i++) {
    value = value * 128 + (c[i] & 0x7f);
    if (!(c[i] & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

function decodeTime(b: Uint8Array, t: Tlv): Date {
  const s = utf8(content(b, t));
  const m = t.tag === 0x17
    ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s)
    : /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s);
  if (!m) throw new JwsError("bad_certificate");
  let year = Number(m[1]);
  if (t.tag === 0x17) year += year < 50 ? 2000 : 1900;
  return new Date(Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])));
}

function parseCertificate(der: Uint8Array): Certificate {
  const cert = readTlv(der, 0);
  const [tbsTlv, sigAlgTlv, sigTlv] = children(der, cert);
  if (!tbsTlv || !sigAlgTlv || !sigTlv) throw new JwsError("bad_certificate");
  const tbs = children(der, tbsTlv);
  const o = tbs[0].tag === 0xa0 ? 1 : 0;
  const [issuerTlv, validityTlv, subjectTlv, spkiTlv] = [tbs[o + 2], tbs[o + 3], tbs[o + 4], tbs[o + 5]];
  if (!spkiTlv) throw new JwsError("bad_certificate");

  const [notBeforeTlv, notAfterTlv] = children(der, validityTlv);
  const spkiAlg = children(der, children(der, spkiTlv)[0]);
  const curveOid = decodeOid(content(der, spkiAlg[1]));
  const curve = curveOid === "1.2.840.10045.3.1.7" ? "P-256" : curveOid === "1.3.132.0.34" ? "P-384" : null;
  if (!curve) throw new JwsError("bad_certificate", `curve ${curveOid}`);

  const sigAlgOid = decodeOid(content(der, children(der, sigAlgTlv)[0]));
  const signatureHash = sigAlgOid === "1.2.840.10045.4.3.2" ? "SHA-256" : sigAlgOid === "1.2.840.10045.4.3.3" ? "SHA-384" : null;
  if (!signatureHash) throw new JwsError("bad_certificate", `signature ${sigAlgOid}`);

  const extensionOids: string[] = [];
  const extWrapper = tbs.find((t) => t.tag === 0xa3);
  if (extWrapper) {
    for (const ext of children(der, children(der, extWrapper)[0])) {
      extensionOids.push(decodeOid(content(der, children(der, ext)[0])));
    }
  }

  return {
    tbs: bytes(der, tbsTlv),
    issuer: bytes(der, issuerTlv),
    subject: bytes(der, subjectTlv),
    spki: bytes(der, spkiTlv),
    curve,
    signatureHash,
    signature: content(der, sigTlv).subarray(1), // skip the BIT STRING's unused-bits byte
    notBefore: decodeTime(der, notBeforeTlv),
    notAfter: decodeTime(der, notAfterTlv),
    extensionOids,
  };
}

function importEcKey(cert: Certificate): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", cert.spki, { name: "ECDSA", namedCurve: cert.curve }, false, ["verify"]);
}

async function verifyIssuedBy(cert: Certificate, issuer: Certificate) {
  if (!equalBytes(cert.issuer, issuer.subject)) throw new JwsError("bad_chain", "issuer name");
  const size = issuer.curve === "P-256" ? 32 : 48;
  const key = await importEcKey(issuer);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: cert.signatureHash }, key, derToRawSignature(cert.signature, size), cert.tbs);
  if (!ok) throw new JwsError("bad_chain", "certificate signature");
}

/** DER ECDSA-Sig-Value → the fixed-width r‖s form Web Crypto expects. */
export function derToRawSignature(der: Uint8Array, size: number): Uint8Array {
  const seq = readTlv(der, 0);
  const [r, s] = children(der, seq).map((t) => content(der, t));
  if (!r || !s) throw new JwsError("bad_certificate");
  const out = new Uint8Array(size * 2);
  const put = (n: Uint8Array, offset: number) => {
    let i = 0;
    while (i < n.length - 1 && n[i] === 0) i++;
    const v = n.subarray(i);
    if (v.length > size) throw new JwsError("bad_certificate");
    out.set(v, offset + size - v.length);
  };
  put(r, 0);
  put(s, size);
  return out;
}

// --- Encoding helpers ------------------------------------------------------------

function equalBytes(a: Uint8Array, b: Uint8Array) {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

function utf8(b: Uint8Array) {
  return new TextDecoder().decode(b);
}

export function base64Decode(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function base64UrlDecode(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  return base64Decode(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

async function sha256Hex(b: Uint8Array) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", b));
  return Array.from(digest, (v) => v.toString(16).padStart(2, "0")).join("");
}
