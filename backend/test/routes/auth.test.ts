// POST /v1/auth/apple — Sign in with Apple integration tests.
//
// We install the shared drizzle fake and then override `getDefaultAppleJwks`
// so the real `verifyIdentityToken` runs against a locally-generated ES256
// keypair instead of Apple's remote JWKS. That keeps the production verifier
// code path under test (issuer, audience, exp, signature) while removing the
// network dependency.

import { describe, it, expect, beforeAll, beforeEach, vi } from 'vitest';
import { SignJWT, generateKeyPair, type JWTVerifyGetKey } from 'jose';
import {
  installDrizzleFake,
  resetStore,
  resetKv,
  store,
  TEST_ENV,
  ctx,
  seedDevice,
} from '../support';

installDrizzleFake();

interface TestKeys {
  privateKey: CryptoKey;
  jwks: JWTVerifyGetKey;
}

const keys: TestKeys = {} as TestKeys;

import worker from '~/index';
import { __setDefaultAppleJwksForTests } from '~/services/appleAuth';

async function post(
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  return worker.fetch(
    new Request(`https://api.fastsha.red${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify(body),
    }),
    TEST_ENV,
    ctx,
  );
}

async function signAppleIdentityToken(
  payload: Record<string, unknown>,
  opts: { issuer?: string; audience?: string; expSecondsFromNow?: number } = {},
): Promise<string> {
  const issuer = opts.issuer ?? 'https://appleid.apple.com';
  const audience = opts.audience ?? TEST_ENV.APPLE_BUNDLE_ID;
  const now = Math.floor(Date.now() / 1000);
  const exp = now + (opts.expSecondsFromNow ?? 600);
  return new SignJWT(payload)
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key-0' })
    .setIssuer(issuer)
    .setAudience(audience)
    .setIssuedAt(now)
    .setExpirationTime(exp)
    .sign(keys.privateKey);
}

describe('POST /v1/auth/apple', () => {
  beforeAll(async () => {
    const pair = await generateKeyPair('RS256', { extractable: true });
    // Build a local "JWKS" resolver: jose's `jwtVerify` accepts either a
    // CryptoKey directly or a (header, jws) => Promise<CryptoKey> function.
    // We use the function form so the signature matches the production
    // surface (`createRemoteJWKSet` returns a function); it ignores the kid
    // because we only sign with one key.
    keys.privateKey = pair.privateKey;
    const getKey: JWTVerifyGetKey = async () => pair.publicKey;
    keys.jwks = getKey;
    __setDefaultAppleJwksForTests(getKey);
  });

  beforeEach(() => {
    resetStore();
    resetKv();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('happy path: creates user + device and returns tokens', async () => {
    const identityToken = await signAppleIdentityToken({
      sub: '001234.apple-sub-abc.5678',
      email: 'buyer@privaterelay.appleid.com',
      email_verified: 'true',
      is_private_email: 'true',
    });

    const res = await post('/v1/auth/apple', {
      identityToken,
      authorizationCode: 'c.apple-code-fixture',
      fullName: 'Ada Lovelace',
      platform: 'ios',
      appVersion: '0.2.0',
    });

    expect(res.status).toBe(201);
    const body = (await res.json()) as {
      deviceToken: string;
      userId: string;
      isNewUser: boolean;
    };
    expect(body.isNewUser).toBe(true);
    expect(body.deviceToken.length).toBeGreaterThan(10);
    expect(body.userId.length).toBeGreaterThan(0);

    expect(store.users.length).toBe(1);
    const userRow = store.users[0]!;
    expect(userRow.appleUserId).toBe('001234.apple-sub-abc.5678');
    expect(userRow.email).toBe('buyer@privaterelay.appleid.com');
    expect(userRow.fullName).toBe('Ada Lovelace');

    // The new device row belongs to the user.
    expect(store.devices.length).toBe(1);
    expect(store.devices[0]!.userId).toBe(userRow.id);
  });

  it('rejects a token signed for the wrong audience (401)', async () => {
    const identityToken = await signAppleIdentityToken(
      { sub: '001234.apple-sub-xyz.0001' },
      { audience: 'com.some.other.app' },
    );
    const res = await post('/v1/auth/apple', {
      identityToken,
      authorizationCode: 'c',
      platform: 'ios',
    });
    expect(res.status).toBe(401);
    const body = (await res.json()) as { code?: string; detail?: string };
    expect(body.code).toBe('unauthorized');
    expect(body.detail ?? '').toContain('invalid_identity_token');
    expect(store.users.length).toBe(0);
  });

  it('rejects a token with the wrong issuer (401)', async () => {
    const identityToken = await signAppleIdentityToken(
      { sub: '001234.apple-sub-iss.0002' },
      { issuer: 'https://accounts.google.com' },
    );
    const res = await post('/v1/auth/apple', {
      identityToken,
      authorizationCode: 'c',
      platform: 'ios',
    });
    expect(res.status).toBe(401);
  });

  it('rejects an expired token (401)', async () => {
    const identityToken = await signAppleIdentityToken(
      { sub: '001234.apple-sub-exp.0003' },
      { expSecondsFromNow: -60 },
    );
    const res = await post('/v1/auth/apple', {
      identityToken,
      authorizationCode: 'c',
      platform: 'ios',
    });
    expect(res.status).toBe(401);
  });

  it('claim flow: attaches an existing anonymous device to the new user', async () => {
    const { deviceId, token: anonymousToken } = await seedDevice();
    expect(store.devices[0]!.userId).toBeNull();

    const identityToken = await signAppleIdentityToken({
      sub: '001234.apple-sub-claim.0004',
      email: 'claimer@example.com',
      email_verified: 'true',
    });

    const res = await post('/v1/auth/apple', {
      identityToken,
      authorizationCode: 'c',
      claimDeviceToken: anonymousToken,
      platform: 'ios',
    });
    expect(res.status).toBe(201);
    const body = (await res.json()) as { userId: string; isNewUser: boolean };
    expect(body.isNewUser).toBe(true);

    // Seeded device now belongs to the user; a second row was minted too.
    const seeded = store.devices.find((d) => d.id === deviceId)!;
    expect(seeded.userId).toBe(body.userId);
    expect(store.devices.length).toBe(2);
  });

  it('returning user: same sub returns existing userId and isNewUser=false', async () => {
    const sub = '001234.apple-sub-return.0005';

    const firstToken = await signAppleIdentityToken({ sub, email: 'first@example.com' });
    const first = await post('/v1/auth/apple', {
      identityToken: firstToken,
      authorizationCode: 'c',
      fullName: 'Returning User',
      email: 'first@example.com',
      platform: 'ios',
    });
    expect(first.status).toBe(201);
    const firstBody = (await first.json()) as { userId: string; isNewUser: boolean };
    expect(firstBody.isNewUser).toBe(true);

    // Apple omits fullName/email on every authorization after the first.
    const secondToken = await signAppleIdentityToken({ sub });
    const second = await post('/v1/auth/apple', {
      identityToken: secondToken,
      authorizationCode: 'c',
      platform: 'ios',
    });
    expect(second.status).toBe(201);
    const secondBody = (await second.json()) as { userId: string; isNewUser: boolean };
    expect(secondBody.isNewUser).toBe(false);
    expect(secondBody.userId).toBe(firstBody.userId);

    // One user row, still carrying the metadata we captured on the first call.
    expect(store.users.length).toBe(1);
    const userRow = store.users[0]!;
    expect(userRow.email).toBe('first@example.com');
    expect(userRow.fullName).toBe('Returning User');
  });

  it('malformed identity token → 401 without DB writes', async () => {
    const res = await post('/v1/auth/apple', {
      identityToken: 'not-a-jwt.still-not-a-jwt.nope',
      authorizationCode: 'c',
      platform: 'ios',
    });
    expect(res.status).toBe(401);
    expect(store.users.length).toBe(0);
    expect(store.devices.length).toBe(0);
  });

  it('rejects body missing identityToken (400 validation_error)', async () => {
    const res = await post('/v1/auth/apple', { authorizationCode: 'c', platform: 'ios' });
    expect(res.status).toBe(400);
  });
});
