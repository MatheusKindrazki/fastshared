import { UnzipInflate, UnzipPassThrough } from 'fflate';

export class UnpackFailure extends Error {
  constructor(
    public readonly code: string,
    message = code,
  ) {
    super(message);
  }
}

interface Entry {
  path: string;
  compressed: number;
  original: number;
  method: number;
  offset: number;
  directory: boolean;
}

const MAX_ENTRIES = 2000;
const MAX_FILE = 100 * 1024 * 1024;
const MAX_CENTRAL = 8 * 1024 * 1024;

function u16(b: DataView, n: number): number {
  return b.getUint16(n, true);
}
function u32(b: DataView, n: number): number {
  return b.getUint32(n, true);
}

function normalizePath(path: string): string {
  if (
    !path ||
    path.startsWith('/') ||
    /^[A-Za-z]:/.test(path) ||
    path.includes('\\') ||
    path.includes('\0')
  )
    throw new UnpackFailure('unsafe_path');
  const parts = path.split('/').filter((part) => part && part !== '.');
  if (parts.some((part) => part === '..' || /%(?:2e|2f|5c)/i.test(part)))
    throw new UnpackFailure('unsafe_path');
  const result = parts.join('/');
  if (!result) throw new UnpackFailure('unsafe_path');
  return result;
}

async function range(
  bucket: R2Bucket,
  key: string,
  offset: number,
  length: number,
): Promise<Uint8Array> {
  const object = await bucket.get(key, { range: { offset, length } });
  if (!object) throw new UnpackFailure('invalid_zip');
  return new Uint8Array(await object.arrayBuffer());
}

async function readEntries(
  bucket: R2Bucket,
  key: string,
  size: number,
  cap: number,
): Promise<Entry[]> {
  const tailOffset = Math.max(0, size - 65557);
  const tail = await range(bucket, key, tailOffset, size - tailOffset);
  const tailView = new DataView(tail.buffer, tail.byteOffset, tail.byteLength);
  let eocd = -1;
  for (let i = tail.length - 22; i >= 0; i--) {
    if (u32(tailView, i) === 0x06054b50 && i + 22 + u16(tailView, i + 20) === tail.length) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new UnpackFailure('invalid_zip');
  const count = u16(tailView, eocd + 10);
  const centralSize = u32(tailView, eocd + 12);
  const centralOffset = u32(tailView, eocd + 16);
  if (count > MAX_ENTRIES) throw new UnpackFailure('too_many_entries');
  if (
    count === 0 ||
    count === 65535 ||
    centralSize > MAX_CENTRAL ||
    centralSize === 0xffffffff ||
    centralOffset === 0xffffffff ||
    centralOffset + centralSize > size
  )
    throw new UnpackFailure('invalid_zip');
  const central = await range(bucket, key, centralOffset, centralSize);
  const view = new DataView(central.buffer, central.byteOffset, central.byteLength);
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const entries: Entry[] = [];
  const seen = new Set<string>();
  let totalCompressed = 0;
  let totalOriginal = 0;
  let p = 0;
  for (let i = 0; i < count; i++) {
    if (p + 46 > central.length || u32(view, p) !== 0x02014b50)
      throw new UnpackFailure('invalid_zip');
    const flags = u16(view, p + 8);
    const method = u16(view, p + 10);
    const compressed = u32(view, p + 20);
    const original = u32(view, p + 24);
    const nameLength = u16(view, p + 28);
    const extraLength = u16(view, p + 30);
    const commentLength = u16(view, p + 32);
    const external = u32(view, p + 38);
    const offset = u32(view, p + 42);
    if (
      p + 46 + nameLength + extraLength + commentLength > central.length ||
      flags & 1 ||
      ![0, 8].includes(method)
    )
      throw new UnpackFailure('invalid_zip');
    let raw: string;
    try {
      raw = decoder.decode(central.subarray(p + 46, p + 46 + nameLength));
    } catch {
      throw new UnpackFailure('invalid_zip');
    }
    const path = normalizePath(raw);
    const directory = raw.endsWith('/');
    const mode = external >>> 16;
    const fileType = mode & 0o170000;
    if (fileType && fileType !== (directory ? 0o040000 : 0o100000))
      throw new UnpackFailure('unsafe_entry');
    if (seen.has(path)) throw new UnpackFailure('duplicate_path');
    seen.add(path);
    if (!directory) {
      if (original > MAX_FILE) throw new UnpackFailure('file_too_large');
      if (original > 0 && (compressed === 0 || original / compressed > 100))
        throw new UnpackFailure('compression_ratio');
      totalCompressed += compressed;
      totalOriginal += original;
      if (totalOriginal > cap) throw new UnpackFailure('total_too_large');
    }
    entries.push({ path, compressed, original, method, offset, directory });
    p += 46 + nameLength + extraLength + commentLength;
  }
  if (
    p !== central.length ||
    (totalOriginal > 0 && totalOriginal / Math.max(totalCompressed, 1) > 100)
  )
    throw new UnpackFailure('compression_ratio');
  return entries;
}

function resolveEntry(entries: Entry[]): { entryPath: string; strip: string } {
  const files = entries.filter((e) => !e.directory).map((e) => e.path);
  if (files.includes('index.html')) return { entryPath: 'index.html', strip: '' };
  const folders = new Set(files.map((path) => path.split('/')[0]));
  if (folders.size === 1) {
    const folder = files[0]!.split('/')[0]!;
    if (files.includes(`${folder}/index.html`))
      return { entryPath: 'index.html', strip: `${folder}/` };
  }
  const html = files.filter((path) => path.toLowerCase().endsWith('.html'));
  if (html.length === 1) return { entryPath: html[0]!, strip: '' };
  throw new UnpackFailure('no_entry');
}

export function publicationContentType(path: string): string {
  const ext = path.toLowerCase().split('.').pop() ?? '';
  const types: Record<string, string> = {
    html: 'text/html; charset=utf-8',
    css: 'text/css; charset=utf-8',
    js: 'text/javascript; charset=utf-8',
    mjs: 'text/javascript; charset=utf-8',
    json: 'application/json',
    txt: 'text/plain; charset=utf-8',
    svg: 'image/svg+xml',
    png: 'image/png',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    gif: 'image/gif',
    webp: 'image/webp',
    ico: 'image/x-icon',
    pdf: 'application/pdf',
    woff: 'font/woff',
    woff2: 'font/woff2',
    ttf: 'font/ttf',
    wasm: 'application/wasm',
    mp4: 'video/mp4',
    webm: 'video/webm',
    mp3: 'audio/mpeg',
  };
  return types[ext] ?? 'application/octet-stream';
}

async function extractOne(
  bucket: R2Bucket,
  sourceKey: string,
  entry: Entry,
  destinationKey: string,
  contentType: string,
): Promise<void> {
  const header = await range(bucket, sourceKey, entry.offset, 30);
  const h = new DataView(header.buffer, header.byteOffset, header.byteLength);
  if (u32(h, 0) !== 0x04034b50 || u16(h, 8) !== entry.method)
    throw new UnpackFailure('invalid_zip');
  const start = entry.offset + 30 + u16(h, 26) + u16(h, 28);
  if (entry.compressed === 0 && entry.original === 0) {
    await bucket.put(destinationKey, new Uint8Array(0), { httpMetadata: { contentType } });
    return;
  }
  const compressedObject = await bucket.get(sourceKey, {
    range: { offset: start, length: entry.compressed },
  });
  if (!compressedObject) throw new UnpackFailure('invalid_zip');
  const stream =
    typeof FixedLengthStream === 'undefined'
      ? new TransformStream<Uint8Array, Uint8Array>()
      : new FixedLengthStream(entry.original);
  const writer = stream.writable.getWriter();
  const put = bucket.put(destinationKey, stream.readable, { httpMetadata: { contentType } });
  const decoder = entry.method === 0 ? new UnzipPassThrough() : new UnzipInflate();
  let written = 0;
  const writes: Promise<void>[] = [];
  let error: Error | null = null;
  decoder.ondata = (err, chunk) => {
    if (err) {
      error = err;
      return;
    }
    written += chunk.length;
    if (written > entry.original || written > MAX_FILE) {
      error = new UnpackFailure('file_too_large');
      return;
    }
    writes.push(writer.write(chunk));
  };
  const reader = compressedObject.body.getReader();
  let consumed = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      for (let i = 0; i < value.length; i += 64 * 1024) {
        const part = value.subarray(i, i + 64 * 1024);
        consumed += part.length;
        decoder.push(part, consumed === entry.compressed);
        await Promise.all(writes.splice(0));
        if (error) throw error;
      }
    }
    if (consumed !== entry.compressed || written !== entry.original)
      throw new UnpackFailure('invalid_zip');
    await writer.close();
    await put;
  } catch (err) {
    await writer.abort(err).catch(() => undefined);
    await put.catch(() => undefined);
    throw err;
  }
}

export async function unpackPublicationZip(
  bucket: R2Bucket,
  sourceKey: string,
  size: number,
  publicationId: string,
  number: number,
  cap: number,
) {
  const entries = await readEntries(bucket, sourceKey, size, cap);
  const { entryPath, strip } = resolveEntry(entries);
  const files: Array<{ path: string; storageKey: string; contentType: string; sizeBytes: number }> =
    [];
  try {
    for (const entry of entries) {
      if (entry.directory) continue;
      const path = strip ? entry.path.slice(strip.length) : entry.path;
      if (!path) continue;
      const storageKey = `pub/${publicationId}/v${number}/${path}`;
      const contentType = publicationContentType(path);
      await extractOne(bucket, sourceKey, entry, storageKey, contentType);
      files.push({ path, storageKey, contentType, sizeBytes: entry.original });
    }
  } catch (err) {
    await Promise.all(files.map((file) => bucket.delete(file.storageKey).catch(() => undefined)));
    throw err;
  }
  return { entryPath, files };
}
