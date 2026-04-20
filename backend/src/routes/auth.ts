import { Hono } from 'hono';
import { and, eq, isNull, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb, type Db } from '~/db/client';
import { device, user, type User } from '~/db/schema';
import { createDevice, hashDeviceToken } from '~/services/devices';
import {
  AppleAuthError,
  verifyIdentityToken,
  type VerifiedAppleIdentity,
} from '~/services/appleAuth';
import { toBase64Url } from '~/lib/hash';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { log } from '~/lib/logger';

// Body schema — mirrors what ASAuthorizationAppleIDCredential exposes on the
// client. `identityToken` + `authorizationCode` are always present on a
// successful authorization; `fullName` and `email` are ONLY populated on the
// first authorization of a bundle identifier per Apple ID, so both are
// optional. `claimDeviceToken` lets a caller promote an anonymous device to
// the newly-authenticated user without losing its upload history.
const appleSignInSchema = z.object({
  identityToken: z.string().min(20),
  authorizationCode: z.string().min(1),
  fullName: z.string().min(1).max(256).optional(),
  email: z.string().email().max(256).optional(),
  claimDeviceToken: z.string().min(1).max(256).optional(),
  platform: z.enum(['ios', 'ipados', 'macos']),
  appVersion: z.string().min(1).max(64).optional(),
});

type AppleSignInInput = z.infer<typeof appleSignInSchema>;

export const authRoutes = new Hono<AppBindings>();

// Unauthenticated — this IS the auth handshake. Rate-limit by IP so a
// leaked client secret can't be used to enumerate accounts / flood inserts.
// Window matches /v1/devices (10 / 10 min) because a successful sign-in
// always issues a device token, so the two buckets are roughly equivalent
// in cost and abuse profile.
authRoutes.use(
  '/apple',
  ratelimit({ bucket: 'auth_apple', limit: 10, windowSeconds: 600, keyFrom: 'ip' }),
);

authRoutes.post('/apple', async (c) => {
  const body: AppleSignInInput = appleSignInSchema.parse(await c.req.json());

  // 1. Verify the identity token. Any failure here is a 401 — we never
  //    trust the claims without a valid signature + matching audience.
  let identity: VerifiedAppleIdentity;
  try {
    identity = await verifyIdentityToken({
      identityToken: body.identityToken,
      audience: c.env.APPLE_BUNDLE_ID,
    });
  } catch (err) {
    const reason =
      err instanceof AppleAuthError ? err.reason : err instanceof Error ? err.name : 'unknown';
    log.warn({
      msg: 'auth_apple_token_invalid',
      requestId: c.get('requestId'),
      reason,
    });
    return problem(c, 401, 'unauthorized', 'Unauthorized', `invalid_identity_token:${reason}`);
  }

  const db = createDb(c.env.DATABASE_URL);

  // 2. Resolve-or-create the user row. `apple_user_id` is the canonical key;
  //    email/fullName are best-effort metadata Apple only sends on the first
  //    authorization.
  const { row: userRow, isNewUser } = await upsertUserByAppleSub(db, {
    sub: identity.sub,
    // Prefer Apple's verified email over whatever the client posted: the
    // token is signed, the request body is not. Fall back to the client
    // value so Private Relay users whose token omits email can still bind
    // a contact address on first sign-in.
    email: identity.email ?? body.email ?? null,
    fullName: body.fullName ?? null,
  });

  // 3. Optionally claim an existing anonymous device so its upload history
  //    follows the user. Silent no-op when the token doesn't match — we
  //    never fail the sign-in on a stale claim attempt.
  if (body.claimDeviceToken) {
    const claimHash = await hashDeviceToken(body.claimDeviceToken, c.env.DEVICE_TOKEN_PEPPER);
    await db
      .update(device)
      .set({ userId: userRow.id, lastSeenAt: sql`now()` })
      .where(and(eq(device.tokenHash, claimHash), isNull(device.userId)));
  }

  // 4. Mint a new device row owned by this user. We always issue a fresh
  //    token; the client is expected to discard any prior anonymous token
  //    after a successful sign-in.
  const tokenBytes = new Uint8Array(32);
  crypto.getRandomValues(tokenBytes);
  const newDeviceToken = toBase64Url(tokenBytes);
  const newDeviceTokenHash = await hashDeviceToken(newDeviceToken, c.env.DEVICE_TOKEN_PEPPER);

  const createdDevice = await createDevice({
    db,
    tokenHash: newDeviceTokenHash,
    platform: body.platform,
    appVersion: body.appVersion ?? '0.0.0',
  });

  // createDevice() doesn't take userId (existing contract we don't want to
  // change for the anonymous /v1/devices path), so set it in a follow-up
  // update. Cheap — one row by primary key.
  if (createdDevice.userId !== userRow.id) {
    await db.update(device).set({ userId: userRow.id }).where(eq(device.id, createdDevice.id));
  }

  return c.json(
    {
      deviceToken: newDeviceToken,
      userId: userRow.id,
      isNewUser,
    },
    201,
  );
});

// -- helpers ------------------------------------------------------------------

interface UpsertUserArgs {
  sub: string;
  email: string | null;
  fullName: string | null;
}

async function upsertUserByAppleSub(
  db: Db,
  args: UpsertUserArgs,
): Promise<{ row: User; isNewUser: boolean }> {
  const existing = await db.select().from(user).where(eq(user.appleUserId, args.sub)).limit(1);

  if (existing[0]) {
    const row = existing[0];
    // Fill in metadata Apple only sent us on the first authorization — but
    // ONLY if the current stored value is null, so a user who later changes
    // their email in Apple ID doesn't blow away our copy.
    const patch: Partial<User> = {};
    if (args.email && !row.email) patch.email = args.email;
    if (args.fullName && !row.fullName) patch.fullName = args.fullName;
    if (Object.keys(patch).length > 0) {
      const [updated] = await db
        .update(user)
        .set({ ...patch, updatedAt: sql`now()` })
        .where(eq(user.id, row.id))
        .returning();
      return { row: updated ?? row, isNewUser: false };
    }
    return { row, isNewUser: false };
  }

  const [inserted] = await db
    .insert(user)
    .values({
      appleUserId: args.sub,
      email: args.email,
      fullName: args.fullName,
    })
    .returning();
  if (!inserted) throw new Error('user insert returned no rows');
  return { row: inserted, isNewUser: true };
}
