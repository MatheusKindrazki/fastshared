# Fast Uploads — 4-Tier Implementation Plan

**Owner:** Matheus · **Scope:** iOS/macOS client + Hono Worker + Neon · **Drafted:** 2026-04-20

## Context

The product's promise is one-tap share → link on clipboard. Today the clipboard lands only **after** the file finishes uploading. For a 50 MB file on cellular (~20 Mbps), that's 15–25 seconds of "did anything happen?" UX. The in-app progress banner (shipped in TestFlight build 198808087) softens this, but the core issue is still: **link-on-clipboard is gated on upload completion**. This plan decouples them and adds throughput optimizations.

**Pipeline today:**

```
pick → stage (fs copy) → sha256 stream (50MB ≈ 200-500ms) → presign POST (≈100ms)
     → URLSession uploadTask fromFile (SINGLE PUT) → /complete → shortUrl → clipboard
```

**Physical floor** on 20 Mbps cellular: 50 MB = ~20s. You cannot beat the speed of light. But **perceived** speed is about when "Link copied!" fires — that can be <1s regardless of file size.

## Goals & Success Criteria

| Metric | Today | Target | Tier responsible |
|---|---|---|---|
| Time-to-clipboard (50 MB, wifi) | ~8s | **<1s** | Tier 1 |
| Time-to-clipboard (50 MB, LTE) | ~20s | **<1.5s** | Tier 1 |
| Actual upload throughput (50 MB, wifi 100 Mbps) | ~5s (single PUT) | **~1.5-2s** (multipart parallel) | Tier 2 |
| Presign latency (startup overhead) | 400–600ms | **~100ms** | Tier 3 |
| Cold-launch first upload warm-up | ~250ms overhead | **~50ms** | Tier 4 |

**Non-goals:**
- Client-side compression — explicitly rejected in project memory (`upload-compression.md`). Files go byte-for-byte.
- Single-connection optimizations (HTTP/3, QUIC tuning) — URLSession handles these transparently.
- Changes to R2 storage / retention policy.

## Tier Summary

| Tier | Change | Files touched | Migration? | Impact | Effort |
|---|---|---|---|---|---|
| **1** | Server mints `share_link` at presign (status `pending`); client copies shortUrl on presign response; worker serves "uploading…" page for pending links | Backend 4, Worker 1, Client 2, Migration 1 | ✅ `0004_pending_link.sql` | **Massive UX** | M |
| **2** | Multipart PUT for files > 5 MB; parallel part upload (3–4 in-flight) | Backend 3, Client 2 | No | **Real throughput 2-4x** (on good networks) | M–L |
| **3** | Parallelize sha256 with presign; relax `sha256` requirement on presign, accept on `/complete` | Backend 1, Client 1 | No | Startup -200-400ms | S |
| **4** | URLSession warm-up on launch, `httpMaximumConnectionsPerHost`, pre-stage during picker dismiss | Client 2 | No | ~200ms cold-launch | S |

**Dependencies:**
- Tiers are **independent** and can ship in any order.
- Recommended order: **1 → 3 → 4 → 2** (Tier 1 biggest UX win, Tier 3 small free win, Tier 4 polish, Tier 2 when product is stable since it changes the upload contract).

---

## Shared Conventions

### Testing strategy

- Every backend change gets a vitest test (pattern: `backend/test/<route>.test.ts`).
- Client changes tested via Xcode unit tests for state transitions; UI manually smoke-tested per TestFlight build.
- Migrations tested by applying against a branch Neon DB, checking idempotency (`IF NOT EXISTS`, ON CONFLICT clauses).
- Each Tier lands behind an `APP_ENV` guard when non-trivial (currently not needed — see "Rollout" per Tier).

### Breaking changes

- Tier 1: adds new state (`pending`). Backward-compatible: existing clients that ignore the new `shortUrl` on presign still work; the worker serving a "pending" page to a new-client link won't break.
- Tier 2: adds optional `mode: 'multipart'` to presign response. Client falls back to single PUT if mode is absent. Fully backward-compatible.
- Tier 3: loosens presign request schema (`sha256` becomes truly optional on initial presign, mandatory at `/complete`). Old clients always send sha256 and keep working.
- Tier 4: no contract change.

### Observability

Every tier adds structured logs with `requestId`, `clientJobId`, and the phase (`presign`, `multipart-part-N`, `complete`, `clipboard-copied`). Useful when diagnosing "user says it didn't work" reports.

---

# Tier 1 — Optimistic Short URL *(biggest perceived-speed win)*

## Overview

Today the share_link row is created only at `/complete`, after the bytes finish. In the dedup case (`tryDedupResponse` at `backend/src/routes/uploads.ts:274-314`) it's already created at presign time and the shortUrl is returned immediately — the client copies instantly. We generalize that pattern to **every** upload:

1. **Presign** creates a `share_link` row with `linkStatus = 'pending'`, returns `{ uploadId, upload, shortUrl, token, expiresAt, deleteAfter }`.
2. **Client** copies `shortUrl` to clipboard the moment presign returns. User sees "Link copied!" in <1s.
3. **Bytes upload** in background via URLSession.
4. **/complete** flips `linkStatus` from `pending` to `active`.
5. **Worker `/s/:token`** serves a branded "Uploading… ready in ~15s" page for pending links, with auto-refresh via `<meta refresh>` or client-side polling.

Recipients who land on a pending link see a countdown page matching our ephemeral brand. When the upload completes, the page self-refreshes into the normal preview. This is actually *on-brand* — the whole product is "watch a link's state change over time."

## Phases

### 1.1 Migration: add `pending` to link status enum

**File:** `backend/drizzle/0004_pending_link.sql` (new)

```sql
BEGIN;

-- Relax the CHECK constraint to allow 'pending' alongside active/expired/revoked.
-- We pull the old constraint name from pg_catalog because Drizzle's migration
-- 0001 named it inline; the name is schema-dependent.
DO $$
DECLARE
  cname text;
BEGIN
  SELECT conname INTO cname
  FROM pg_constraint
  WHERE conrelid = 'share_link'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%link_status%';
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE share_link DROP CONSTRAINT %I', cname);
  END IF;
END $$;

ALTER TABLE share_link
  ADD CONSTRAINT share_link_link_status_check
  CHECK (link_status IN ('pending', 'active', 'expired', 'revoked'));

-- Fast path for pending-link cleanup cron (see phase 1.6).
CREATE INDEX IF NOT EXISTS share_link_pending_idx
  ON share_link (link_status, created_at)
  WHERE link_status = 'pending';

COMMIT;
```

**Verify:** `psql "$DATABASE_URL" -f drizzle/0004_pending_link.sql` — must complete without errors. Re-run must be a no-op (drop is guarded by lookup; constraint add fails if already added, so wrap in `DO $$ BEGIN EXCEPTION WHEN duplicate_object THEN NULL; END $$` if needed in practice).

### 1.2 Backend schema: extend link status enum

**File:** `backend/src/db/schema.ts:101-102`

```diff
- export const LINK_STATUSES = ['active', 'expired', 'revoked'] as const;
+ export const LINK_STATUSES = ['pending', 'active', 'expired', 'revoked'] as const;
```

No other schema change needed — the column is already `text`. Zod types auto-update.

### 1.3 Backend: presign creates pending share_link

**File:** `backend/src/routes/uploads.ts:89-137` (presign path, fresh uploads)

Replace the fresh-path section:

```typescript
// Generate the token + short URL up front. We insert a share_link row
// with status='pending' so the URL is REAL from the moment presign returns.
// /complete (below) flips it to 'active' once R2 confirms bytes landed.
const shareToken = await generateToken(c.env.SHORT_LINK_TOKEN_LENGTH ?? 18);
const now = new Date();
const expiresAt = computeExpiresAt(policy, now);
const deleteAfter = computeDeleteAfter(expiresAt, policy);

await db.transaction(async (tx) => {
  // Upsert upload_job as before (lines 89-109 replaced here).
  await tx.insert(uploadJob).values({ ... }).onConflictDoUpdate({ ... });

  // NEW: pre-create share_link in pending state.
  await tx.insert(shareLink).values({
    token: shareToken,
    assetId: /* deferred — null reference is set at /complete */,
    visibility: 'public',
    expiresAt,
    linkStatus: 'pending',
    retentionPolicy: policy,
  });
});
```

**⚠️ Schema change required:** `share_link.asset_id` is `NOT NULL` today (line 113 of schema.ts). Relax it to nullable OR create a tombstone asset row with `status='pending'`. Recommendation: **nullable is cleaner**:

```sql
-- Add to the SAME 0004 migration:
ALTER TABLE share_link ALTER COLUMN asset_id DROP NOT NULL;
```

And in `schema.ts:115`:
```diff
- assetId: uuid('asset_id').notNull().references(() => asset.id),
+ assetId: uuid('asset_id').references(() => asset.id),
```

Readers (`loadActiveLinkAndAsset` at redirect.ts:55) must tolerate `null assetId` for pending links — handled in phase 1.5.

**Presign response** (`presignResponse()` at uploads.ts:364):

```typescript
return c.json({
  uploadId: job.id,
  bucket, storageKey, contentType, sizeBytes,
  upload: { url, method, headers, expiresAt: presignExpiresAt },
  retentionPolicy: policy,
  expiresAt, deleteAfter,
  // NEW:
  token: shareToken,
  shortUrl: `${c.env.SHORT_LINK_HOST}/s/${shareToken}`,
  linkStatus: 'pending',
});
```

### 1.4 Backend: `/complete` flips pending → active, links asset

**File:** `backend/src/routes/uploads.ts:140-243`

At `/complete`, instead of inserting a new `share_link`, **update the existing pending one** to attach `assetId` and flip status:

```typescript
// Inside the transaction at lines 208-238:
const [createdAsset] = await tx.insert(asset).values({ ... }).returning();

// Was: tx.insert(shareLink).values({...})
// Now: update the pending share_link created at presign.
const [updatedLink] = await tx
  .update(shareLink)
  .set({
    assetId: createdAsset.id,
    linkStatus: 'active',
  })
  .where(and(
    eq(shareLink.token, /* token comes from upload_job or request */),
    eq(shareLink.linkStatus, 'pending'),
  ))
  .returning();

if (!updatedLink) {
  // Edge case: pending link was deleted by cron (stale) or complete is
  // called twice. Fall back to inserting fresh.
  await tx.insert(shareLink).values({ ... linkStatus: 'active' });
}
```

**How /complete knows the token:** Store it on the `upload_job` row at presign. Add migration step to 0004:

```sql
ALTER TABLE upload_job ADD COLUMN IF NOT EXISTS pending_share_link_token text;
```

And `schema.ts` `uploadJob`:
```typescript
pendingShareLinkToken: text('pending_share_link_token'),
```

Presign sets it; /complete reads it.

### 1.5 Worker: serve "uploading" preview for pending links

**File:** `backend/src/routes/redirect.ts:55-82` (`loadActiveLinkAndAsset`)

```typescript
// New branch BEFORE the expiry check:
if (link.linkStatus === 'pending') {
  return { status: 'pending', link };
}
```

Add to `LoadResult`:
```typescript
| { status: 'pending'; link: ShareLink }
```

At `dispatchHandler:84-135`, new branch:
```typescript
if (loaded.status === 'pending') {
  // Serve the "still uploading" page. The asset row doesn't exist yet,
  // so we can't show filename/size from asset — we pull them from upload_job
  // via the pending_share_link_token lookup.
  const job = await db
    .select({ filename: uploadJob.originalFilename, sizeBytes: uploadJob.sizeBytes })
    .from(uploadJob)
    .where(eq(uploadJob.pendingShareLinkToken, loaded.link.token))
    .limit(1);
  return renderPendingPage({
    filename: job[0]?.filename ?? 'upload',
    sizeBytes: Number(job[0]?.sizeBytes ?? 0),
    expiresAt: loaded.link.expiresAt,
    canonicalUrl: `${c.env.SHORT_LINK_HOST}/s/${token}`,
  });
}
```

### 1.6 Worker: new `renderPendingPage` template

**File:** `backend/src/lib/previewPage.ts`

Add a new exported function `renderPendingPage`. Match the dark branded aesthetic of the new preview page. Specs:

- Full-screen dark ink bg with the radial gradients.
- Center card: `fastshared` wordmark, large animated spinning violet-hot ring (CSS keyframes, reduced-motion friendly), filename below, "Uploading…" label in mono, total size, a soft "This page will auto-refresh. Come back in a moment." hint.
- `<meta http-equiv="refresh" content="5">` for auto-refresh every 5s. Simple, zero-JS.
- Plus: inline `<script>` that polls `HEAD /s/:token/raw` every 3s; when the response goes from 404/410-pending to 200, `location.reload()` (so fast uploads don't wait the full 5s meta refresh).
- Same CSP + privacy headers as other preview pages.
- Cap render path at <50ms CPU budget.

### 1.7 Client: copy shortUrl on presign response

**File:** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/UploadService.swift:87-138`

After presign succeeds and before scheduling the upload, copy the shortUrl:

```swift
let presign = try await apiClient.requestUpload(request)

// NEW: opportunistic clipboard. If the server returned a pending shortUrl,
// copy it immediately — the user sees "Link copied" in the banner right
// after the picker dismisses, regardless of how long the upload takes.
if let shortUrl = presign.shortUrl {
    await MainActor.run {
        clipboard.copy(shortUrl.absoluteString)
    }
    // Inform the banner the link is already copied; it transitions to
    // "copied — still uploading" state.
    await MainActor.run {
        UploadProgressMonitor.shared.markLinkReady(
            clientJobId: job.clientJobId,
            shortUrl: shortUrl.absoluteString
        )
    }
}

// Dedup path unchanged — existing fast-path copy still fires.
if let dedupe = presign.deduped { ... }

// Fresh path continues with schedule + Live Activity...
```

**Schema change:** `PresignResponse` type (in `apple/.../Networking/`) gains optional `shortUrl`, `token`, `linkStatus` fields. `UploadProgressMonitor.ActiveUpload` gains a `linkReady: Bool` field (the banner label changes from "Uploading…" to "Link copied — still uploading" when true).

### 1.8 Client: don't re-copy at `/complete`

**File:** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/UploadOrchestrator.swift:145-178` (`recordSuccess`)

Guard the clipboard write so it only fires if the presign-time shortUrl wasn't already copied. The banner still transitions to its final "completed" phase on `/complete`.

```swift
if !job.linkAlreadyCopied {
  clipboard.copy(shortUrl.absoluteString)
}
```

Track `linkAlreadyCopied` on the UploadJob model (transient, not persisted — just a Bool on the in-memory job).

### 1.9 Tests

- `backend/test/uploads.test.ts` — new cases:
  - Fresh presign creates share_link with `linkStatus='pending'` and returns shortUrl.
  - /complete flips pending → active and attaches assetId.
  - /complete is idempotent when called twice (second call is a no-op).
  - Pending share_link cannot be revoked (should throw 400 / pending-not-revocable).
- `backend/test/redirect.test.ts` — new cases:
  - GET `/s/:token` for pending link returns 200 with "Uploading…" HTML, meta refresh present.
  - GET `/s/:token/raw` for pending link returns 404 (file not in R2 yet).
  - After /complete flips to active, redirect serves real preview.

### 1.10 Rollout

- Ship backend + migration in one deploy. Backward-compatible with old clients (they ignore `presign.shortUrl` and follow the old flow).
- Ship client in next TestFlight build. New clients get instant clipboard; old clients keep working.
- Monitor for 48h: `linkStatus='pending'` rows should never accumulate (cron sweep in phase 1.6 for >1h-old pending).

### 1.11 Risks

- **Pending link leaks** — if the upload fails and `/complete` never fires, the pending row lingers. Mitigation: `pendingCleanup` cron job. Run every 15 min, delete pending links older than 1 hour (presign URL is valid 15 min; anything older is abandoned).
- **Recipient clicks link before upload completes** — handled by the "Uploading…" page. Auto-refresh keeps them on-page.
- **Upload fails after clipboard copy** — user has a "broken" link on clipboard. UX concern: the banner transitions to "Upload failed, link won't work" after max retries. Link auto-expires when pending > 1h, so recipient who pastes it hours later sees 410.
- **Revoke semantics** — user cancels upload. Current revoke endpoint requires `linkStatus='active'`; extend to allow revoking pending links (cancels the upload task too).

---

# Tier 3 — Parallelize SHA-256 with Presign *(small free win)*

Schedule this BEFORE Tier 2 because it's tiny and lowers baseline latency for all paths.

## Phases

### 3.1 Backend: make sha256 optional in presign schema

**File:** `backend/src/routes/uploads.ts:20-48` — `createUploadSchema`

Already optional (`sha256: z.string()...optional()`). But the dedup branch (lines 81-84) requires it. Restructure:

```typescript
if (body.sha256) {
  const dedup = await tryDedupResponse({ ... body.sha256 ... });
  if (dedup) return c.json(dedup);
}
// else: skip dedup, proceed with fresh presign. Client will send sha256
// at /complete for asset metadata storage (and a lazy dedup opportunity
// server-side). This means clients that hash-in-parallel skip the dedup
// fast-path on the first upload of a file — that's the explicit trade.
```

**File:** `backend/src/routes/uploads.ts:164-172` — `completeSchema`

Make `sha256` required at `/complete`:
```diff
- sha256: z.string().regex(/^[a-f0-9]{64}$/).optional(),
+ sha256: z.string().regex(/^[a-f0-9]{64}$/),
```

This is a tighter contract. Old clients always sent it at presign; new clients send it at /complete. Both satisfy `/complete`'s new requirement.

### 3.2 Client: parallelize hash + presign

**File:** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/UploadService.swift:77-87`

Replace sequential hash-then-presign with `async let`:

```swift
// Was:
// job.sha256 = try await SHA256Streamer.hash(fileAt: stagedURL)
// let presign = try await apiClient.requestUpload(PresignRequest(..., sha256: job.sha256, ...))

// Now: kick off both concurrently. Presign completes in ~100ms;
// hash typically completes in 100-500ms. On the wire they overlap,
// so the total startup latency drops from hash+presign to max(hash, presign).
async let hashFuture = SHA256Streamer.hash(fileAt: stagedURL)
async let presignFuture = apiClient.requestUpload(PresignRequest(
  clientJobId: job.clientJobId,
  contentType: contentType,
  sizeBytes: size,
  sha256: nil,    // NEW: don't wait for hash. /complete carries it.
  originalFilename: originalFilename,
  retentionPolicy: retentionPolicy.rawValue,
  customTtlSeconds: nil
))

let (sha, presign) = try await (hashFuture, presignFuture)
job.sha256 = sha
```

Client sends sha256 at `/complete` (already does — no client change needed there).

### 3.3 Trade-off documented

Add a comment at the call site explaining that parallelization **skips server-side dedup on the first upload of a new file hash**. Server can still dedup on `/complete` (look up same-sha256 asset after bytes land), but that's a deferred exercise. For now: acceptable trade (dedup is a nice-to-have, startup speed is a must-have).

### 3.4 Tests

- `FastSharedCoreTests/UploadServiceTests` — new case: presign called with `sha256: null`, upload proceeds, `/complete` receives sha256. Mock `APIClient` verifies both calls.
- `backend/test/uploads.test.ts` — existing test where presign is called without sha256 should still pass; verify dedup fast-path is NOT triggered.

### 3.5 Rollout

- Backend change is relaxation-only; ship first.
- Client follows in any future TestFlight.
- No migration.

### 3.6 Risks

- **Dedup rate drop** — if many users re-share the same file, some first-uploads will miss dedup. Mitigation: add a `/complete` dedup check (post-upload, lookup by sha256, delete the fresh asset + redirect share_link to the canonical asset). That's a Tier-3.5 follow-up, not a blocker.

---

# Tier 4 — Polish *(cold-start micro-wins)*

## Phases

### 4.1 Prewarm URLSession on app launch

**File:** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/BackgroundSessionManager.swift:25-36`

The session is created lazily on first `scheduleUpload`. Pre-warm on app launch so the first upload doesn't pay the ~150-250ms cost of creating the session, registering the delegate, and bootstrapping the background daemon.

Add to `BackgroundSessionManager`:

```swift
public func prewarm() {
  // Touching the session property triggers lazy creation and daemon registration.
  _ = session
}
```

Call from `FastSharedApp.init()` at `apple/FastSharedApp/FastSharedApp.swift`:

```swift
background.bind(orchestrator: orchestrator, store: store)
background.prewarm()   // NEW
```

### 4.2 Optimize connection pooling

**File:** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/BackgroundSessionManager.swift:25-36`

Current config has no explicit `httpMaximumConnectionsPerHost`. URLSession default is 6, which is fine for single-PUT today but becomes a bottleneck for multipart (Tier 2). Set it explicitly:

```swift
configuration.httpMaximumConnectionsPerHost = 6
configuration.timeoutIntervalForRequest = 60
configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60  // 7 days — matches longest retention window.
```

### 4.3 Pre-stage during picker dismiss

**File:** `apple/FastSharedApp/Scenes/HistoryView.swift:490` (`handleImport`)

Today the file copy to staging happens inside `enqueueDrop`. We can start the staging copy **concurrent with the picker's dismiss animation** (the dismiss takes ~300ms). Just wrap the enqueue in a `Task` that fires immediately instead of after a state-settle.

Already does this via `Task {}` — but verify the task priority is `.userInitiated`:

```swift
Task(priority: .userInitiated) {
  do { _ = try await service.enqueueDrop(urls: urls) } catch { ... }
}
```

### 4.4 No tests

These are all perf tweaks with no functional change. Validate via manual launch-to-first-upload timing with Instruments.

### 4.5 Rollout

Ship with any TestFlight build that also has Tier 1 or 3. No backend change.

---

# Tier 2 — Multipart Upload *(real throughput)*

**Schedule last.** Biggest code surface, and the UX wins of Tiers 1+3 make single-PUT uploads feel fast enough that multipart is icing.

## Overview

Split files > 5 MB into 5–10 MB parts, upload in parallel (3-4 in-flight), aggregate progress client-side, send `/complete` with multipart completion payload. Server consolidates parts into one R2 object via `CompleteMultipartUpload`.

## Phases

### 2.1 Backend: multipart presign

**File:** `backend/src/services/r2.ts` — add:

```typescript
export async function createMultipartUpload(env: Env, key: string, contentType: string): Promise<{ uploadId: string }> { ... }
export async function presignPart(env: Env, key: string, uploadId: string, partNumber: number): Promise<string> { ... }
export async function completeMultipartUpload(env: Env, key: string, uploadId: string, parts: Array<{ PartNumber: number; ETag: string }>): Promise<void> { ... }
export async function abortMultipartUpload(env: Env, key: string, uploadId: string): Promise<void> { ... }
```

Implement using `@aws-sdk/client-s3` commands (`CreateMultipartUploadCommand`, `UploadPartCommand` presigned, `CompleteMultipartUploadCommand`, `AbortMultipartUploadCommand`). The existing `ListMultipartUploads` and `Abort` stubs at `r2.ts:156-168` confirm the cleanup side already works.

### 2.2 Backend: extend presign response with multipart plan

**File:** `backend/src/routes/uploads.ts:89-137`

```typescript
const MULTIPART_THRESHOLD = 5 * 1024 * 1024;  // 5 MB
const PART_SIZE = 8 * 1024 * 1024;             // 8 MB — R2 minimum is 5, S3 SDK recommends ≥5 and ≤5 GB.

if (body.sizeBytes <= MULTIPART_THRESHOLD) {
  // Single PUT (today's path).
  return c.json({ ..., upload: { mode: 'single', url, method: 'PUT', headers, expiresAt }, ... });
}

// Multipart path.
const { uploadId } = await createMultipartUpload(c.env, storageKey, body.contentType);
const partCount = Math.ceil(body.sizeBytes / PART_SIZE);
const parts = await Promise.all(
  Array.from({ length: partCount }, (_, i) => presignPart(c.env, storageKey, uploadId, i + 1))
);

return c.json({
  ...,
  upload: {
    mode: 'multipart',
    uploadId,
    partSize: PART_SIZE,
    parts: parts.map((url, i) => ({ partNumber: i + 1, url, method: 'PUT' })),
    expiresAt
  },
  ...
});
```

### 2.3 Backend: `/complete` accepts multipart payload

**File:** `backend/src/routes/uploads.ts:140-243`

```typescript
const completeSchema = z.object({
  contentType: z.string().min(1).max(128),
  sizeBytes: z.number().int().positive(),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  originalFilename: z.string().min(1).max(512).optional(),
  // NEW — for multipart:
  multipart: z.object({
    uploadId: z.string(),
    parts: z.array(z.object({
      partNumber: z.number().int().positive(),
      eTag: z.string(),
    })).min(1),
  }).optional(),
});
```

If `multipart` is present, call `completeMultipartUpload` BEFORE the `headObject` size verification. Otherwise, same path as today.

### 2.4 Client: multipart upload coordinator

**File:** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/MultipartUploader.swift` (new, ~200 lines)

New actor that:
1. Takes the multipart plan from presign response.
2. Reads file in `PART_SIZE` chunks (stream, don't buffer the whole file).
3. Uploads each part via `URLSession.uploadTask(with:fromData:)` (can't use `fromFile:` directly for ranged reads — construct a part-file, OR use `httpBodyStream`, OR slice with `FileHandle.read` into a temp `Data`).
4. Maintains a concurrent queue of 3 in-flight part tasks (`TaskGroup` with semaphore).
5. Aggregates progress: sums `countOfBytesSent` across all in-flight tasks; reports to `UploadProgressMonitor.updateProgress` and `LiveActivityController.updateProgress`.
6. On all parts complete, collects ETags and calls `apiClient.completeMultipartUpload(uploadId, parts:)`.
7. On failure: abort multipart upload (call backend endpoint that aborts R2 multipart), mark job failed.

### 2.5 Client: pick path based on size

**File:** `apple/Packages/FastSharedCore/Sources/FastSharedCore/Upload/UploadService.swift` — after presign:

```swift
switch presign.upload.mode {
case "single":
  try background.scheduleUpload(job: job, upload: presign.upload.single, fileURL: stagedURL)
case "multipart":
  try await multipartUploader.start(job: job, plan: presign.upload.multipart, fileURL: stagedURL)
}
```

### 2.6 Tests

- Backend: integration test uploading a 12 MB payload through multipart endpoints, verifying the R2 object matches byte-for-byte.
- Client: unit test for `MultipartUploader` that mocks URLSession, verifies 3 concurrent parts, retry behavior on 503, abort on too many retries.
- E2E: TestFlight test with a 50 MB + 200 MB file.

### 2.7 Rollout

- Backend ships first (new endpoints live, old clients don't call them → no regression).
- Client ships in a TestFlight with a feature flag (`DEV_OVERRIDES.multipartUpload = true`) to gate the new path until validated.
- Flip flag on for all users after 1 week of sandbox testing.

### 2.8 Risks

- **Multipart abandonment** — parts uploaded but `/complete` never fires (user kills app, network drops). R2 charges for incomplete multiparts. Mitigation: existing `ListMultipartUploads` + `Abort` cron in `r2.ts:116-168` already sweeps abandoned uploads.
- **Part ordering** — S3-compatible APIs require parts in order. `CompleteMultipartUpload` call must pass parts sorted by `partNumber`. Enforce client-side.
- **Resume after app kill** — URLSession background mode handles this for single PUT. For multipart, we need to persist part-level progress to SwiftData so we can resume where we left off. Add migration 0005_multipart_job.
- **Part size vs retry granularity** — 8 MB is a good default. A failed part re-uploads 8 MB, not 50 MB. Good tradeoff.

---

# Sequencing & Timeline

| Week | Tier | Deliverables |
|---|---|---|
| 1 | Tier 3 | Client async-let, backend schema relaxation, tests. ~1 day work. |
| 1 | Tier 4 | Prewarm + pooling config + pre-stage. ~0.5 day. |
| 1 | Tier 1 | Migration + backend + worker + client + pending preview template. 3–4 days. |
| 2 | Tier 1 validation | 48h soak on TestFlight, monitor pending-link leaks, refine cleanup cron. |
| 3+ | Tier 2 | Multipart client + backend. Ship behind flag, validate, flip on. 4–5 days. |

Total: ~10 engineer-days to ship all 4 tiers, with natural validation breaks between 1 and 2.

---

# Open Questions

1. **Pending link revoke UX** — what happens when user cancels an upload mid-flight? Options: (a) delete the pending share_link server-side (the paste becomes a 404 — clean), (b) flip to `revoked` with a "cancelled" reason (paste shows "Sender cancelled this upload" — honest but more work). **Recommend (a)** for simplicity.

2. **Pending link expiry** — what's the max time a pending link can live? R2 presigned URL is valid 15 min; after that, the client can't upload. Mitigation: the `pendingCleanup` cron deletes pending > 1h. Window of 1h is generous for re-try after reconnect.

3. **Multipart threshold** — 5 MB is aggressive (most photos). Consider 10 MB or even 25 MB to limit protocol overhead. **Recommend 10 MB** to start; tune from there.

4. **Clipboard copy on dedup vs presign** — today dedup copies immediately; Tier 1 also copies immediately. Guard against double-copy: check if `linkAlreadyCopied` on the job.

5. **Legal copy on pending preview page** — "This file is being shared with you; it's still uploading." Needs proofing. Keep brand-aligned (ephemerality, restraint). Finalize copy before Tier 1 ships.

---

# Explicitly Out of Scope

- Client-side compression (rejected — see `memory/upload-compression.md`)
- Push-based Live Activity updates from backend (worker would need APNs Live Activity credentials; current progress comes from URLSession delegate locally)
- Peer-to-peer uploads (not a fit for ephemeral share model)
- Image/video transcoding (files go byte-for-byte)
