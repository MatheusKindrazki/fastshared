// App Store Server API client. Three public methods, one factory:
//
//   createAppStoreServerApi(env) → {
//     verifyTransactionJWS(jws): Promise<DecodedTransaction>
//     verifyNotificationJWS(signedPayload): Promise<DecodedNotification>
//     getSubscriptionStatus(originalTransactionId): Promise<SubscriptionStatusResult>
//   }
//
// All three live in the same module so the cert bundle, JWT cache, and
// private helpers are shared without exporting them.
//
// Security-sensitive: the transaction + notification verifiers perform full
// x5c chain verification against Apple's root CA. `getSubscriptionStatus`
// uses a short-lived (30-min) ES256 JWT signed with the ASC p8 private key.

import 'reflect-metadata';
import {
  SignJWT,
  decodeProtectedHeader,
  importPKCS8,
  importX509,
  jwtVerify,
} from 'jose';
import {
  BasicConstraintsExtension,
  KeyUsageFlags,
  KeyUsagesExtension,
  X509Certificate,
} from '@peculiar/x509';
import type { Env } from '~/env';
import { log } from '~/lib/logger';
import type { SubscriptionStatus, SubscriptionTier } from '~/db/schema';
import { deriveTierFromProductId } from '~/services/subscriptions';

export class InvalidJwsError extends Error {
  readonly reason: string;
  constructor(reason: string) {
    super(`invalid_jws: ${reason}`);
    this.name = 'InvalidJwsError';
    this.reason = reason;
  }
}

export class AppStoreApiError extends Error {
  readonly status: number | null;
  readonly reason: string;
  constructor(reason: string, status: number | null = null) {
    super(`app_store_api: ${reason}`);
    this.name = 'AppStoreApiError';
    this.reason = reason;
    this.status = status;
  }
}

export interface DecodedTransaction {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  purchaseDate: Date;
  expiresDate: Date | null;
  environment: 'Production' | 'Sandbox';
  bundleId: string;
  // Raw claims — useful for forensic logging; callers should NOT include in
  // user-facing responses.
  raw: Record<string, unknown>;
}

export interface DecodedRenewalInfo {
  originalTransactionId: string;
  autoRenewStatus: boolean;
  autoRenewProductId: string | null;
  expirationIntent: number | null;
  environment: 'Production' | 'Sandbox';
  raw: Record<string, unknown>;
}

export interface DecodedNotification {
  notificationType: string;
  subtype: string | null;
  notificationUUID: string;
  signedDate: Date;
  version: string;
  data: {
    bundleId: string;
    environment: 'Production' | 'Sandbox';
    signedTransactionInfo: string | null;
    signedRenewalInfo: string | null;
    status: number | null;
    appAppleId: string | null;
  };
  raw: Record<string, unknown>;
}

export interface SubscriptionStatusResult {
  status: number;
  tier: SubscriptionTier;
  expiresDate: Date | null;
  autoRenewStatus: boolean;
  latestTransactionId: string;
  originalTransactionId: string;
  environment: 'Production' | 'Sandbox';
  raw: unknown;
}

// Apple's Production root (AppleRootCA-G3). Stable public anchor; rotating
// this is an App Store-wide event that would be communicated months ahead.
// https://www.apple.com/certificateauthority/
const APPLE_ROOT_CA_G3_PEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

// Cache one signed JWT per distinct `env` reference (same Worker instance).
// Apple accepts up to 60-min JWTs for ASC API — we cap at 25 min so a slightly
// skewed clock never causes a mid-request expiry.
interface JwtCacheEntry {
  jwt: string;
  expiresAt: number;
}
const JWT_CACHE = new WeakMap<object, JwtCacheEntry>();
const JWT_TTL_SECONDS = 25 * 60;
const JWT_HARD_TTL_SECONDS = 30 * 60;

export interface AppStoreServerApi {
  verifyTransactionJWS(jws: string): Promise<DecodedTransaction>;
  verifyNotificationJWS(signedPayload: string): Promise<DecodedNotification>;
  verifyRenewalInfoJWS(jws: string): Promise<DecodedRenewalInfo>;
  getSubscriptionStatus(originalTransactionId: string): Promise<SubscriptionStatusResult>;
}

export function createAppStoreServerApi(env: Env): AppStoreServerApi {
  const apiHost = isProduction(env)
    ? 'https://api.storekit.itunes.apple.com'
    : 'https://api.storekit-sandbox.itunes.apple.com';

  return {
    async verifyTransactionJWS(jws) {
      const claims = await verifyAppleSignedJws(jws);
      return toDecodedTransaction(claims);
    },

    async verifyRenewalInfoJWS(jws) {
      const claims = await verifyAppleSignedJws(jws);
      return toDecodedRenewalInfo(claims);
    },

    async verifyNotificationJWS(signedPayload) {
      const claims = await verifyAppleSignedJws(signedPayload);
      return toDecodedNotification(claims);
    },

    async getSubscriptionStatus(originalTransactionId) {
      const url = `${apiHost}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`;
      const body = await fetchWithRetries(url, async () => buildAuthJwt(env));
      const decoded = await decodeStatusResponse(body, originalTransactionId);
      return decoded;
    },
  };
}

// -- JWT builder --------------------------------------------------------------

export async function buildAuthJwt(env: Env): Promise<string> {
  const cached = JWT_CACHE.get(env as unknown as object);
  const nowMs = Date.now();
  if (cached && cached.expiresAt > nowMs + 60_000) {
    return cached.jwt;
  }
  const privateKey = await loadP8(env);
  const iat = Math.floor(nowMs / 1000);
  const exp = iat + JWT_TTL_SECONDS;
  const jwt = await new SignJWT({ bid: env.APPLE_BUNDLE_ID })
    .setProtectedHeader({ alg: 'ES256', kid: env.APP_STORE_CONNECT_KEY_ID, typ: 'JWT' })
    .setIssuer(env.APP_STORE_CONNECT_ISSUER_ID)
    .setAudience('appstoreconnect-v1')
    .setIssuedAt(iat)
    .setExpirationTime(exp)
    .sign(privateKey);
  JWT_CACHE.set(env as unknown as object, { jwt, expiresAt: nowMs + JWT_HARD_TTL_SECONDS * 1000 });
  return jwt;
}

async function loadP8(env: Env): Promise<CryptoKey> {
  const pem = decodeP8ToPem(env.APP_STORE_CONNECT_P8_KEY_BASE64);
  return importPKCS8(pem, 'ES256');
}

function decodeP8ToPem(b64: string): string {
  // The wrangler secret is the base64-encoded content of the AuthKey_XXX.p8
  // file. Apple's .p8 files already come as a PEM-formatted PKCS8 block (they
  // start with `-----BEGIN PRIVATE KEY-----`); base64-decoding gives us the
  // PEM back directly.
  const decoded = atob(b64);
  if (decoded.includes('BEGIN PRIVATE KEY')) return decoded;
  // If someone stored only the base64 body without PEM armor, wrap it so
  // `importPKCS8` has something to parse. This keeps a minor footgun from
  // turning into a hard crash in the same-Worker cold path.
  const wrapped = [
    '-----BEGIN PRIVATE KEY-----',
    ...chunk(b64, 64),
    '-----END PRIVATE KEY-----',
  ].join('\n');
  return wrapped;
}

function chunk(s: string, size: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < s.length; i += size) out.push(s.slice(i, i + size));
  return out;
}

// -- Verifier (shared) --------------------------------------------------------

async function verifyAppleSignedJws(jws: string): Promise<Record<string, unknown>> {
  if (typeof jws !== 'string' || jws.split('.').length !== 3) {
    throw new InvalidJwsError('malformed_jws');
  }
  let header: { alg?: string; x5c?: string[]; typ?: string };
  try {
    header = decodeProtectedHeader(jws) as typeof header;
  } catch {
    throw new InvalidJwsError('bad_header');
  }
  if (header.alg !== 'ES256') throw new InvalidJwsError('unexpected_alg');
  const chain = header.x5c;
  if (!Array.isArray(chain) || chain.length === 0) {
    throw new InvalidJwsError('missing_x5c');
  }
  const leafPem = await verifyX5cChainAgainstRoot(chain, APPLE_ROOT_CA_G3_PEM);

  const leafKey = await importX509(leafPem, 'ES256');
  try {
    const { payload } = await jwtVerify(jws, leafKey);
    return payload as Record<string, unknown>;
  } catch (err) {
    throw new InvalidJwsError(
      `signature_verify_failed:${err instanceof Error ? err.name : 'unknown'}`,
    );
  }
}

export async function verifyX5cChainAgainstRoot(
  chain: string[],
  trustedRootPem: string,
  now: Date = new Date(),
): Promise<string> {
  if (chain.length < 1) throw new InvalidJwsError('chain_too_short');

  const certs: X509Certificate[] = [];
  const pems: string[] = [];
  try {
    for (const cert of chain) {
      const pem = pemFromBase64(cert);
      pems.push(pem);
      certs.push(new X509Certificate(pem));
    }
  } catch (err) {
    if (err instanceof InvalidJwsError) throw err;
    throw new InvalidJwsError('bad_certificate');
  }

  const root = new X509Certificate(trustedRootPem);
  const lastPem = normalizePem(pems[pems.length - 1] ?? '');
  const rootPem = normalizePem(trustedRootPem);
  const rootIncluded = lastPem === rootPem;
  const path = rootIncluded ? certs : [...certs, root];

  if (path.length < 2) throw new InvalidJwsError('chain_too_short');
  if (rootIncluded && !path[path.length - 1]?.equal(root)) {
    throw new InvalidJwsError('untrusted_root');
  }
  if (!rootIncluded) {
    const last = certs[certs.length - 1];
    if (!last || last.issuer !== root.subject) {
      throw new InvalidJwsError('untrusted_root');
    }
  }

  for (let i = 0; i < path.length - 1; i++) {
    const child = path[i];
    const issuer = path[i + 1];
    if (!child || !issuer) throw new InvalidJwsError('chain_too_short');
    if (child.issuer !== issuer.subject) {
      throw new InvalidJwsError('chain_issuer_mismatch');
    }
    assertIssuerCanSign(issuer, i + 1 === path.length - 1, root);
    const ok = await child.verify({ publicKey: issuer.publicKey, date: now });
    if (!ok) throw new InvalidJwsError('chain_signature_invalid');
  }

  const rootOk = await root.verify({ publicKey: root.publicKey, date: now });
  if (!rootOk) throw new InvalidJwsError('root_signature_invalid');

  return pems[0]!;
}

function assertIssuerCanSign(
  cert: X509Certificate,
  isTrustAnchor: boolean,
  trustedRoot: X509Certificate,
): void {
  const basic = cert.getExtension(BasicConstraintsExtension);
  if (!basic?.ca) throw new InvalidJwsError('issuer_not_ca');
  const keyUsage = cert.getExtension(KeyUsagesExtension);
  if (keyUsage && (keyUsage.usages & KeyUsageFlags.keyCertSign) === 0) {
    throw new InvalidJwsError('issuer_cannot_sign');
  }
  if (!isTrustAnchor) return;
  if (!cert.equal(trustedRoot)) {
    throw new InvalidJwsError('untrusted_root');
  }
}

function pemFromBase64(b64: string | undefined): string {
  if (!b64 || typeof b64 !== 'string') throw new InvalidJwsError('empty_cert_in_chain');
  const lines = chunk(b64.replace(/\s+/g, ''), 64);
  return ['-----BEGIN CERTIFICATE-----', ...lines, '-----END CERTIFICATE-----'].join('\n');
}

function normalizePem(pem: string): string {
  return pem.replace(/\r/g, '').trim();
}

// -- Claims → typed shapes ----------------------------------------------------

function toDecodedTransaction(c: Record<string, unknown>): DecodedTransaction {
  const transactionId = requireString(c, 'transactionId');
  const originalTransactionId = requireString(c, 'originalTransactionId');
  const productId = requireString(c, 'productId');
  const bundleId = requireString(c, 'bundleId');
  const purchaseDate = new Date(requireNumber(c, 'purchaseDate'));
  const expiresRaw = c['expiresDate'];
  const expiresDate =
    typeof expiresRaw === 'number' && Number.isFinite(expiresRaw) ? new Date(expiresRaw) : null;
  const environment = coerceEnvironment(c['environment']);
  return {
    transactionId,
    originalTransactionId,
    productId,
    purchaseDate,
    expiresDate,
    environment,
    bundleId,
    raw: c,
  };
}

function toDecodedRenewalInfo(c: Record<string, unknown>): DecodedRenewalInfo {
  const originalTransactionId = requireString(c, 'originalTransactionId');
  const autoRenewStatus = c['autoRenewStatus'] === 1 || c['autoRenewStatus'] === true;
  const autoRenewProductId =
    typeof c['autoRenewProductId'] === 'string' ? (c['autoRenewProductId'] as string) : null;
  const expirationIntent =
    typeof c['expirationIntent'] === 'number' ? (c['expirationIntent'] as number) : null;
  return {
    originalTransactionId,
    autoRenewStatus,
    autoRenewProductId,
    expirationIntent,
    environment: coerceEnvironment(c['environment']),
    raw: c,
  };
}

function toDecodedNotification(c: Record<string, unknown>): DecodedNotification {
  const notificationType = requireString(c, 'notificationType');
  const subtype = typeof c['subtype'] === 'string' ? (c['subtype'] as string) : null;
  const notificationUUID = requireString(c, 'notificationUUID');
  const signedDate = new Date(requireNumber(c, 'signedDate'));
  const version = typeof c['version'] === 'string' ? (c['version'] as string) : '2.0';
  const data = (c['data'] ?? {}) as Record<string, unknown>;
  const bundleId = requireString(data, 'bundleId');
  const environment = coerceEnvironment(data['environment']);
  const signedTransactionInfo =
    typeof data['signedTransactionInfo'] === 'string'
      ? (data['signedTransactionInfo'] as string)
      : null;
  const signedRenewalInfo =
    typeof data['signedRenewalInfo'] === 'string' ? (data['signedRenewalInfo'] as string) : null;
  const status = typeof data['status'] === 'number' ? (data['status'] as number) : null;
  const appAppleId = typeof data['appAppleId'] === 'string' ? (data['appAppleId'] as string) : null;
  return {
    notificationType,
    subtype,
    notificationUUID,
    signedDate,
    version,
    data: {
      bundleId,
      environment,
      signedTransactionInfo,
      signedRenewalInfo,
      status,
      appAppleId,
    },
    raw: c,
  };
}

function requireString(c: Record<string, unknown>, key: string): string {
  const v = c[key];
  if (typeof v !== 'string' || v.length === 0) {
    throw new InvalidJwsError(`missing_field:${key}`);
  }
  return v;
}

function requireNumber(c: Record<string, unknown>, key: string): number {
  const v = c[key];
  if (typeof v !== 'number' || !Number.isFinite(v)) {
    throw new InvalidJwsError(`missing_field:${key}`);
  }
  return v;
}

function coerceEnvironment(v: unknown): 'Production' | 'Sandbox' {
  if (v === 'Production') return 'Production';
  return 'Sandbox';
}

// -- Status API fetch ---------------------------------------------------------

async function fetchWithRetries(
  url: string,
  getAuth: () => Promise<string>,
): Promise<unknown> {
  const backoffs = [250, 500, 1000];
  let lastErr: unknown = null;
  for (let attempt = 0; attempt <= backoffs.length; attempt++) {
    const token = await getAuth();
    let res: Response;
    try {
      res = await fetch(url, {
        method: 'GET',
        headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
      });
    } catch (err) {
      lastErr = err;
      if (attempt === backoffs.length) {
        throw new AppStoreApiError('network_failure');
      }
      await sleep(backoffs[attempt] ?? 1000);
      continue;
    }
    if (res.status === 429) {
      const retryAfter = parseRetryAfterMs(res.headers.get('retry-after'));
      if (attempt === backoffs.length) {
        throw new AppStoreApiError('rate_limited', 429);
      }
      await sleep(retryAfter ?? backoffs[attempt] ?? 1000);
      continue;
    }
    if (res.status >= 500) {
      if (attempt === backoffs.length) {
        throw new AppStoreApiError(`server_error_${res.status}`, res.status);
      }
      await sleep(backoffs[attempt] ?? 1000);
      continue;
    }
    if (res.status === 401 || res.status === 403) {
      // Auth errors don't retry — JWT is either valid or it's not.
      throw new AppStoreApiError(`unauthorized_${res.status}`, res.status);
    }
    if (res.status === 404) {
      throw new AppStoreApiError('not_found', 404);
    }
    if (!res.ok) {
      throw new AppStoreApiError(`unexpected_${res.status}`, res.status);
    }
    return res.json();
  }
  // Unreachable — guard.
  throw new AppStoreApiError('retries_exhausted', null);
}

function parseRetryAfterMs(header: string | null): number | null {
  if (!header) return null;
  const asInt = Number(header);
  if (Number.isFinite(asInt) && asInt >= 0) return asInt * 1000;
  const asDate = Date.parse(header);
  if (Number.isFinite(asDate)) return Math.max(0, asDate - Date.now());
  return null;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function decodeStatusResponse(
  body: unknown,
  originalTransactionId: string,
): Promise<SubscriptionStatusResult> {
  const outer = body as {
    data?: Array<{
      lastTransactions?: Array<{
        status?: number;
        signedTransactionInfo?: string;
        signedRenewalInfo?: string;
        originalTransactionId?: string;
      }>;
    }>;
    environment?: string;
  };
  const tx = outer.data?.[0]?.lastTransactions?.find(
    (t) => t?.originalTransactionId === originalTransactionId,
  ) ?? outer.data?.[0]?.lastTransactions?.[0];
  if (!tx || !tx.signedTransactionInfo) {
    throw new AppStoreApiError('empty_status_response');
  }
  // These are Apple-signed JWS — round-trip through the notification verifier.
  const txClaims = await verifyAppleSignedJws(tx.signedTransactionInfo);
  const transaction = toDecodedTransaction(txClaims);
  let autoRenewStatus = false;
  if (tx.signedRenewalInfo) {
    try {
      const renewalClaims = await verifyAppleSignedJws(tx.signedRenewalInfo);
      const renewal = toDecodedRenewalInfo(renewalClaims);
      autoRenewStatus = renewal.autoRenewStatus;
    } catch (err) {
      // Renewal info is advisory; log and continue without crashing the flow.
      log.warn({
        msg: 'iap_renewal_info_verify_failed',
        reason: err instanceof InvalidJwsError ? err.reason : 'unknown',
      });
    }
  }
  return {
    status: typeof tx.status === 'number' ? tx.status : 1,
    tier: deriveTierFromProductId(transaction.productId),
    expiresDate: transaction.expiresDate,
    autoRenewStatus,
    latestTransactionId: transaction.transactionId,
    originalTransactionId: transaction.originalTransactionId,
    environment: transaction.environment,
    raw: body,
  };
}

// Map Apple's status int to our SubscriptionStatus enum. Exported because
// both `/verify` and `/webhook` need it.
//   0 = active; 1 = expired; 2 = billing retry; 3 = grace period; 4 = revoked.
// https://developer.apple.com/documentation/appstoreserverapi/status
export function mapAppleStatusInt(s: number): SubscriptionStatus {
  switch (s) {
    case 0:
      return 'active';
    case 1:
      return 'expired';
    case 2:
      return 'in_billing_retry';
    case 3:
      return 'in_grace';
    case 4:
      return 'revoked';
    default:
      return 'expired';
  }
}

function isProduction(env: Env): boolean {
  return env.APP_ENV === 'production';
}
