// Apple Sign in with Apple identity-token verification.
//
// Apple signs identity tokens with RS256 against keys rotated ~weekly. The
// canonical JWKS lives at https://appleid.apple.com/auth/keys. We cache the
// `createRemoteJWKSet` handle at module scope so subsequent requests on the
// same Worker isolate reuse Apple's key material without refetching.
//
// Verification semantics (matches Apple's published contract):
//   - alg = RS256 (enforced by `jose` via the JWKS key's alg hint)
//   - iss = https://appleid.apple.com
//   - aud = env.APPLE_BUNDLE_ID
//   - exp / nbf / iat — enforced by `jose`
//   - `sub` is required; this is the ONLY stable per-user identifier.
//     Never trust `email` as the primary key — Apple Private Relay lets
//     users hide their real address, and the address may be absent entirely
//     on anything but the first authorization.

import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

export const APPLE_ISSUER = 'https://appleid.apple.com';
export const APPLE_JWKS_URL = new URL('https://appleid.apple.com/auth/keys');

export class AppleAuthError extends Error {
  readonly reason: string;
  constructor(reason: string, message?: string) {
    super(message ?? `apple_auth: ${reason}`);
    this.name = 'AppleAuthError';
    this.reason = reason;
  }
}

export interface VerifiedAppleIdentity {
  sub: string;
  email: string | null;
  emailVerified: boolean | null;
  isPrivateEmail: boolean | null;
  raw: Record<string, unknown>;
}

// Default JWKS handle — lazily constructed so test suites can install a stub
// before the first request. `jose`'s implementation caches inside the returned
// function, so holding the reference is enough to reuse the fetched key set.
let defaultJwks: JWTVerifyGetKey | null = null;

export function getDefaultAppleJwks(): JWTVerifyGetKey {
  if (!defaultJwks) {
    defaultJwks = createRemoteJWKSet(APPLE_JWKS_URL);
  }
  return defaultJwks;
}

// Tests inject a locally-generated ES256 key set via this setter so they can
// sign fixtures without hitting Apple's live JWKS endpoint. Pass `null` to
// reset back to the remote-JWKS default. Production callers never use this.
export function __setDefaultAppleJwksForTests(jwks: JWTVerifyGetKey | null): void {
  defaultJwks = jwks;
}

export interface VerifyIdentityTokenArgs {
  identityToken: string;
  audience: string;
  // Injectable for tests — defaults to the Apple-backed remote JWKS.
  jwks?: JWTVerifyGetKey;
}

export async function verifyIdentityToken(
  args: VerifyIdentityTokenArgs,
): Promise<VerifiedAppleIdentity> {
  const { identityToken, audience } = args;
  if (typeof identityToken !== 'string' || identityToken.split('.').length !== 3) {
    throw new AppleAuthError('malformed_token');
  }
  const jwks = args.jwks ?? getDefaultAppleJwks();

  let payload: Record<string, unknown>;
  try {
    const res = await jwtVerify(identityToken, jwks, {
      issuer: APPLE_ISSUER,
      audience,
      algorithms: ['RS256'],
    });
    payload = res.payload as Record<string, unknown>;
  } catch (err) {
    // Map jose errors to a small vocabulary the route can respond with. We
    // intentionally swallow the specific jose error name into `reason` so the
    // caller can log/surface it without exposing the raw message.
    const name = err instanceof Error ? err.name : 'unknown';
    const code = (err as { code?: string }).code ?? '';
    if (code === 'ERR_JWT_EXPIRED' || name === 'JWTExpired') {
      throw new AppleAuthError('expired');
    }
    if (code === 'ERR_JWT_CLAIM_VALIDATION_FAILED' || name === 'JWTClaimValidationFailed') {
      throw new AppleAuthError('claim_invalid');
    }
    if (
      code === 'ERR_JWS_SIGNATURE_VERIFICATION_FAILED' ||
      name === 'JWSSignatureVerificationFailed'
    ) {
      throw new AppleAuthError('signature_invalid');
    }
    throw new AppleAuthError(`verify_failed:${name}`);
  }

  const sub = payload['sub'];
  if (typeof sub !== 'string' || sub.length === 0) {
    throw new AppleAuthError('missing_sub');
  }

  const emailRaw = payload['email'];
  const email = typeof emailRaw === 'string' && emailRaw.length > 0 ? emailRaw : null;

  // `email_verified` / `is_private_email` are sent as the strings "true" /
  // "false" by Apple (documented). Normalise to booleans, tolerating real
  // booleans too in case the shape ever shifts.
  const emailVerified = coerceBooleanish(payload['email_verified']);
  const isPrivateEmail = coerceBooleanish(payload['is_private_email']);

  return {
    sub,
    email,
    emailVerified,
    isPrivateEmail,
    raw: payload,
  };
}

function coerceBooleanish(v: unknown): boolean | null {
  if (typeof v === 'boolean') return v;
  if (v === 'true') return true;
  if (v === 'false') return false;
  return null;
}
