import { eq, sql } from 'drizzle-orm';
import type { Db } from '~/db/client';
import { device, type Device, type NewDevice } from '~/db/schema';
import { hmacSha256Hex } from '~/lib/hash';

export async function hashDeviceToken(rawToken: string, pepper: string): Promise<string> {
  return hmacSha256Hex(pepper, rawToken);
}

export interface CreateDeviceArgs {
  db: Db;
  tokenHash: string;
  platform: string;
  appVersion: string;
}

export async function createDevice(args: CreateDeviceArgs): Promise<Device> {
  const row: NewDevice = {
    tokenHash: args.tokenHash,
    platform: args.platform,
    appVersion: args.appVersion,
  };
  const [inserted] = await args.db.insert(device).values(row).returning();
  if (!inserted) throw new Error('device insert returned no rows');
  return inserted;
}

export async function findDeviceByTokenHash(db: Db, tokenHash: string): Promise<Device | null> {
  const rows = await db.select().from(device).where(eq(device.tokenHash, tokenHash)).limit(1);
  return rows[0] ?? null;
}

export async function touchLastSeen(db: Db, deviceId: string): Promise<void> {
  await db
    .update(device)
    .set({ lastSeenAt: sql`now()` })
    .where(eq(device.id, deviceId));
}
