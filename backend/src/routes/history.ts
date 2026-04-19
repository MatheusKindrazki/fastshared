import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { and, desc, eq, lt, ne, or } from 'drizzle-orm';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { asset, shareLink } from '~/db/schema';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';

export const historyRoutes = new Hono<AppBindings>();

historyRoutes.use('*', auth());
historyRoutes.use('*', ratelimit({ bucket: 'history', limit: 300, windowSeconds: 3600 }));

const querySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().positive().max(100).optional(),
});

interface Cursor {
  createdAt: string;
  id: string;
}

function encodeCursor(c: Cursor): string {
  const json = JSON.stringify(c);
  const bytes = new TextEncoder().encode(json);
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i] ?? 0);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function decodeCursor(s: string): Cursor | null {
  try {
    const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
    const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + pad;
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const parsed = JSON.parse(new TextDecoder().decode(bytes)) as unknown;
    if (
      parsed &&
      typeof parsed === 'object' &&
      typeof (parsed as Cursor).createdAt === 'string' &&
      typeof (parsed as Cursor).id === 'string'
    ) {
      return parsed as Cursor;
    }
    return null;
  } catch {
    return null;
  }
}

historyRoutes.get('/', async (c) => {
  const query = querySchema.parse({
    cursor: c.req.query('cursor') ?? undefined,
    limit: c.req.query('limit') ?? undefined,
  });
  const deviceId = c.get('deviceId');
  if (!deviceId) throw new HTTPException(401, { message: 'no device' });

  const limit = query.limit ?? 50;
  const cursor = query.cursor ? decodeCursor(query.cursor) : null;
  const db = createDb(c.env.DATABASE_URL);

  // Returns tombstones too (expired/revoked/deleted) so the client can render
  // the full 30-day history with per-row badges. Server-side effectiveLinkStatus
  // reconciles any row where expires_at has slipped past without a reconciler pass.
  const whereClauses = [eq(asset.ownerDeviceId, deviceId), ne(asset.status, 'deleted')];
  if (cursor) {
    whereClauses.push(
      or(
        lt(asset.createdAt, new Date(cursor.createdAt)),
        and(eq(asset.createdAt, new Date(cursor.createdAt)), lt(asset.id, cursor.id)),
      )!,
    );
  }

  const rows = await db
    .select({
      id: asset.id,
      contentType: asset.contentType,
      sizeBytes: asset.sizeBytes,
      originalFilename: asset.originalFilename,
      status: asset.status,
      createdAt: asset.createdAt,
      deleteAfter: asset.deleteAfter,
      deletedAt: asset.deletedAt,
      token: shareLink.token,
      expiresAt: shareLink.expiresAt,
      linkStatus: shareLink.linkStatus,
      retentionPolicy: shareLink.retentionPolicy,
      accessCount: shareLink.accessCount,
    })
    .from(asset)
    .leftJoin(shareLink, eq(shareLink.assetId, asset.id))
    .where(and(...whereClauses))
    .orderBy(desc(asset.createdAt), desc(asset.id))
    .limit(limit + 1);

  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  const now = Date.now();

  const items = page.map((r) => {
    const effectiveLinkStatus = resolveEffectiveStatus(r.linkStatus, r.expiresAt, r.deletedAt, now);
    return {
      assetId: r.id,
      contentType: r.contentType,
      sizeBytes: Number(r.sizeBytes),
      originalFilename: r.originalFilename,
      status: r.status,
      createdAt: r.createdAt.toISOString(),
      deleteAfter: r.deleteAfter.toISOString(),
      deletedAt: r.deletedAt ? r.deletedAt.toISOString() : null,
      token: r.token,
      shortUrl: r.token ? `${c.env.SHORT_LINK_HOST}/s/${r.token}` : null,
      expiresAt: r.expiresAt ? r.expiresAt.toISOString() : null,
      linkStatus: effectiveLinkStatus,
      retentionPolicy: r.retentionPolicy,
      accessCount: r.accessCount === null ? 0 : Number(r.accessCount),
    };
  });

  const last = page[page.length - 1];
  const nextCursor =
    hasMore && last ? encodeCursor({ createdAt: last.createdAt.toISOString(), id: last.id }) : null;

  return c.json({ items, nextCursor });
});

function resolveEffectiveStatus(
  linkStatus: string | null,
  expiresAt: Date | null,
  deletedAt: Date | null,
  nowMs: number,
): string | null {
  if (!linkStatus) return null;
  if (deletedAt) return 'expired';
  if (linkStatus === 'active' && expiresAt && expiresAt.getTime() <= nowMs) return 'expired';
  return linkStatus;
}
