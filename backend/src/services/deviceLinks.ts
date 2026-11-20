import { and, eq, gt, isNull } from 'drizzle-orm';
import type { Db } from '~/db/client';
import { deviceLinkCode } from '~/db/schema';
import { hmacSha256Hex } from '~/lib/hash';

export const LINK_CODE_TTL_MS = 10 * 60 * 1000;

function randomCode(): string {
  // Rejection sampling keeps the 6 digits uniform.
  const buf = new Uint32Array(1);
  for (;;) {
    crypto.getRandomValues(buf);
    const n = buf[0]!;
    if (n < 4_294_000_000) return String(n % 1_000_000).padStart(6, '0');
  }
}

async function hashCode(pepper: string, code: string): Promise<string> {
  return hmacSha256Hex(pepper, `device-link:${code}`);
}

export async function createLinkCode(
  db: Db,
  pepper: string,
  args: { userId: string; deviceId: string },
): Promise<{ code: string; expiresAt: Date }> {
  const code = randomCode();
  const expiresAt = new Date(Date.now() + LINK_CODE_TTL_MS);
  await db.insert(deviceLinkCode).values({
    codeHash: await hashCode(pepper, code),
    userId: args.userId,
    createdByDeviceId: args.deviceId,
    expiresAt,
  });
  return { code, expiresAt };
}

// Consumes the code exactly once. Returns the account it belongs to, or null
// when the code is unknown, expired or already used.
export async function claimLinkCode(
  db: Db,
  pepper: string,
  args: { code: string; deviceId: string },
): Promise<string | null> {
  const codeHash = await hashCode(pepper, args.code);
  const [claimed] = await db
    .update(deviceLinkCode)
    .set({ consumedAt: new Date(), consumedByDeviceId: args.deviceId })
    .where(
      and(
        eq(deviceLinkCode.codeHash, codeHash),
        isNull(deviceLinkCode.consumedAt),
        gt(deviceLinkCode.expiresAt, new Date()),
      ),
    )
    .returning();
  return claimed?.userId ?? null;
}
