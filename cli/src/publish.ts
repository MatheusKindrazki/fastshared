import { realpath, stat } from 'node:fs/promises';
import path from 'node:path';
import {
  FastSharedApi,
  FastSharedHttpError,
  type PublicationCreateBody,
  type PublicationKind,
  type PublicationOpens,
  type PublicationReady,
  type PublicationRevocation,
  type PublicationSummary,
} from './api.js';
import { UsageError } from './options.js';
import { stageArchiveFiles, stageInputs, type StagedUpload } from './stage.js';

export interface PreparedPublication extends StagedUpload {
  kind: PublicationKind;
}

export interface PublishedPublication {
  id: string;
  slug: string;
  url: string;
  version: number;
  fileCount: number;
  totalBytes: number;
}

export class CommandError extends Error {
  readonly exitCode: number;
  readonly code?: string;
  readonly upgradeUrl?: string;

  constructor(message: string, exitCode: number, extra?: { code?: string; upgradeUrl?: string }) {
    super(message);
    this.exitCode = exitCode;
    if (extra?.code) this.code = extra.code;
    if (extra?.upgradeUrl) this.upgradeUrl = extra.upgradeUrl;
  }
}

const UNPACK_MESSAGES: Record<string, string> = {
  compression_ratio: 'This archive was rejected because its compression ratio is too high.',
  duplicate_path: 'This archive contains the same path more than once.',
  file_too_large: 'A file in this archive is too large to publish. Each file must be 100 MB or smaller.',
  invalid_zip: 'This archive could not be read as a zip file.',
  no_entry:
    'This site has no HTML entry. Include index.html at the root, or a single top-level folder that contains index.html.',
  too_many_entries: 'This archive has too many files to publish. A publication accepts at most 2000 entries.',
  total_too_large: 'This archive is larger than the publication size limit.',
  unsafe_entry: 'This archive contains an entry that is not a regular file or directory.',
  unsafe_path:
    'This archive contains a path that is not allowed. Use relative paths without parent segments or backslashes.',
};

export function publicationPollSettings(env: NodeJS.ProcessEnv): { pollIntervalMs: number; pollTimeoutMs: number } {
  return {
    pollIntervalMs: positiveInt(env.FASTSHARED_PUBLICATION_POLL_INTERVAL_MS, 500),
    pollTimeoutMs: positiveInt(env.FASTSHARED_PUBLICATION_POLL_TIMEOUT_MS, 60_000),
  };
}

export async function preparePublication(inputPath: string, cwd: string): Promise<PreparedPublication> {
  const resolved = path.resolve(cwd, inputPath);
  let info: Awaited<ReturnType<typeof stat>>;
  try {
    info = await stat(resolved);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
      throw new UsageError(`path not found: ${inputPath}`);
    }
    throw err;
  }
  const real = await realpath(resolved);
  if (info.isDirectory()) {
    const staged = await stageInputs([real], { cwd });
    return { ...staged, kind: 'site' };
  }
  if (!info.isFile()) throw new UsageError('publish expects a file or directory.');

  const extension = path.extname(real).toLowerCase();
  if (extension === '.html') {
    const staged = await stageArchiveFiles(
      [{ fsPath: real, archivePath: 'index.html' }],
      `${path.basename(real, path.extname(real))}.zip`,
    );
    return { ...staged, kind: 'site' };
  }
  const staged = await stageInputs([real], { cwd });
  if (extension === '.pdf') return { ...staged, kind: 'pdf' };
  return { ...staged, kind: 'file' };
}

export async function publishLocalPath(args: {
  api: FastSharedApi;
  deviceToken: string;
  cwd: string;
  inputPath: string;
  title?: string;
  update?: string;
  pollIntervalMs: number;
  pollTimeoutMs: number;
  onProgress?: (message: string) => void;
}): Promise<PublishedPublication> {
  const prepared = await preparePublication(args.inputPath, args.cwd);
  try {
    const label = args.update ? `Updating ${args.update}` : `Publishing ${prepared.kind}`;
    args.onProgress?.(`${label} (${prepared.filename}, ${prepared.sizeBytes} bytes)...`);
    return await publishPrepared({
      api: args.api,
      deviceToken: args.deviceToken,
      prepared,
      ...(args.title ? { title: args.title } : {}),
      ...(args.update ? { update: args.update } : {}),
      pollIntervalMs: args.pollIntervalMs,
      pollTimeoutMs: args.pollTimeoutMs,
      ...(args.onProgress ? { onProgress: args.onProgress } : {}),
    });
  } finally {
    await prepared.cleanup();
  }
}

export async function listPublications(api: FastSharedApi, deviceToken: string): Promise<PublicationSummary[]> {
  return api.listPublications(deviceToken);
}

export async function revokePublication(
  api: FastSharedApi,
  deviceToken: string,
  idOrSlug: string,
): Promise<PublicationRevocation> {
  return api.revokePublication(idOrSlug, deviceToken);
}

export async function publicationOpens(
  api: FastSharedApi,
  deviceToken: string,
  idOrSlug: string,
): Promise<PublicationOpens> {
  return api.publicationOpens(idOrSlug, deviceToken);
}

export function formatPublicationList(items: PublicationSummary[]): string {
  if (items.length === 0) return 'No publications.\n';
  return items
    .map((item) => {
      const expiry = item.expiresAt ? `\texpires ${item.expiresAt}` : '';
      const title = item.title ? `\t${item.title}` : '';
      return `${item.url}\t${item.status}\tv${item.version}\t${item.kind}\t${item.opens7d} opens/7d${expiry}${title}\n`;
    })
    .join('');
}

export function formatOpens(opens: PublicationOpens): string {
  if (opens.versions.length === 0) return 'No opens.\n';
  return opens.versions
    .map((version) => `v${version.version}\t${version.count}\t${version.lastOpenedAt ?? '-'}\n`)
    .join('');
}

export function formatRevocation(revocation: PublicationRevocation): string {
  return `revoked ${revocation.id}\n`;
}

async function publishPrepared(args: {
  api: FastSharedApi;
  deviceToken: string;
  prepared: PreparedPublication;
  title?: string;
  update?: string;
  pollIntervalMs: number;
  pollTimeoutMs: number;
  onProgress?: (message: string) => void;
}): Promise<PublishedPublication> {
  const body: PublicationCreateBody = {
    kind: args.prepared.kind,
    filename: args.prepared.filename,
    contentType: args.prepared.contentType,
    sizeBytes: args.prepared.sizeBytes,
    ...(args.title ? { title: args.title } : {}),
  };
  const slot = await callPublication(
    args.update
      ? args.api.createPublicationVersion(args.update, body, args.deviceToken)
      : args.api.createPublication(body, args.deviceToken),
    Boolean(args.update),
  );
  await args.api.putPublicationObject(args.prepared.filePath, slot.upload);
  const completion = await callPublication(
    args.api.completePublication(slot.id, slot.version, args.deviceToken),
    false,
  );
  const ready =
    completion.state === 'ready'
      ? completion.ready
      : await waitUntilReady({
          api: args.api,
          deviceToken: args.deviceToken,
          id: slot.id,
          version: slot.version,
          pollIntervalMs: args.pollIntervalMs,
          pollTimeoutMs: args.pollTimeoutMs,
          ...(completion.pollPath ? { pollPath: completion.pollPath } : {}),
          ...(completion.retryAfterMs !== undefined ? { retryAfterMs: completion.retryAfterMs } : {}),
          ...(args.onProgress ? { onProgress: args.onProgress } : {}),
        });
  return {
    id: ready.id ?? slot.id,
    slug: ready.slug ?? slot.slug,
    url: ready.url,
    version: ready.version,
    fileCount: ready.fileCount,
    totalBytes: ready.totalBytes,
  };
}

async function waitUntilReady(args: {
  api: FastSharedApi;
  deviceToken: string;
  id: string;
  version: number;
  pollIntervalMs: number;
  pollTimeoutMs: number;
  pollPath?: string;
  retryAfterMs?: number;
  onProgress?: (message: string) => void;
}): Promise<PublicationReady> {
  const deadline = Date.now() + args.pollTimeoutMs;
  let pollTarget = args.pollPath ?? `/v1/publications/${encodeURIComponent(args.id)}/versions/${args.version}`;
  let delay = args.retryAfterMs ?? args.pollIntervalMs;
  args.onProgress?.('Publication is processing...');
  while (Date.now() < deadline) {
    const remaining = deadline - Date.now();
    const wait = Math.min(Math.max(delay, 0), remaining);
    if (wait > 0) await sleep(wait);
    if (Date.now() >= deadline) break;
    const completion = await callPublication(args.api.pollPublication(pollTarget, args.deviceToken), false);
    if (completion.state === 'ready') return completion.ready;
    if (completion.pollPath) pollTarget = completion.pollPath;
    delay = completion.retryAfterMs ?? args.pollIntervalMs;
  }
  throw new CommandError(`Publication is still processing after ${args.pollTimeoutMs}ms.`, 1, {
    code: 'publication_timeout',
  });
}

async function callPublication<T>(work: Promise<T>, updating: boolean): Promise<T> {
  try {
    return await work;
  } catch (err) {
    rethrowPublication(err, updating);
  }
}

function rethrowPublication(err: unknown, updating: boolean): never {
  if (updating && err instanceof FastSharedHttpError && err.status === 402) {
    throw new CommandError('Same-URL updates are a Pro feature', 2, {
      code: 'payment_required',
      ...(err.upgradeUrl ? { upgradeUrl: err.upgradeUrl } : {}),
    });
  }
  if (err instanceof FastSharedHttpError) {
    const code = unpackCode(err);
    if (code) {
      throw new CommandError(UNPACK_MESSAGES[code] ?? `The publication archive was rejected (${code}).`, 1, {
        code,
      });
    }
  }
  throw err instanceof Error ? err : new Error(String(err));
}

function unpackCode(err: FastSharedHttpError): string | undefined {
  if (err.unpackError && err.unpackError in UNPACK_MESSAGES) return err.unpackError;
  if (err.unpackError) return err.unpackError;
  if (err.code && err.code in UNPACK_MESSAGES) return err.code;
  if (err.code === 'unpack_error') return 'unpack_error';
  return undefined;
}

function positiveInt(raw: string | undefined, fallback: number): number {
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) return fallback;
  return Math.floor(value);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
