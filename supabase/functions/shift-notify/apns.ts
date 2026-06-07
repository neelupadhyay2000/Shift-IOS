// SHIFT-644/645: token-based (.p8) APNs auth + HTTP/2 send.
//
// Uses the APNs provider-token (JWT, ES256) auth scheme so one auth key serves
// both APNs hosts. The key material comes from Supabase secrets (SHIFT-645) —
// never the repo. The provider token is cached and reused (APNs allows up to 60
// min; we refresh at 50).

export interface ApnsConfig {
  keyId: string; // APNS_KEY_ID — the .p8's 10-char Key ID
  teamId: string; // APNS_TEAM_ID — Apple Developer Team ID
  privateKeyPem: string; // APNS_PRIVATE_KEY — full .p8 PEM contents
  bundleId: string; // APNS_BUNDLE_ID — apns-topic
}

export interface ApnsResult {
  token: string;
  status: number;
  reason?: string;
}

const APNS_HOST = {
  prod: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

let cachedToken: { jwt: string; iat: number } | null = null;

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function providerToken(cfg: ApnsConfig): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.iat < 50 * 60) return cachedToken.jwt;

  const header = base64url(JSON.stringify({ alg: "ES256", kid: cfg.keyId, typ: "JWT" }));
  const claims = base64url(JSON.stringify({ iss: cfg.teamId, iat: now }));
  const signingInput = `${header}.${claims}`;

  const key = await importPrivateKey(cfg.privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  const jwt = `${signingInput}.${base64url(new Uint8Array(signature))}`;
  cachedToken = { jwt, iat: now };
  return jwt;
}

/** Sends one alert push to one device, choosing the host by the token's environment. */
export async function sendApns(
  cfg: ApnsConfig,
  deviceToken: string,
  environment: string,
  payload: Record<string, unknown>,
): Promise<ApnsResult> {
  const jwt = await providerToken(cfg);
  const host = environment === "prod" ? APNS_HOST.prod : APNS_HOST.sandbox;

  const response = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": cfg.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });

  let reason: string | undefined;
  if (response.status !== 200) {
    try {
      reason = (await response.json())?.reason;
    } catch {
      // APNs may return an empty body; status alone is enough.
    }
  }
  return { token: deviceToken, status: response.status, reason };
}
