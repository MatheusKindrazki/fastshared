import { describe, expect, it } from 'vitest';
import { strToU8, zipSync } from 'fflate';
import {
  UnpackFailure,
  unpackPublicationZip,
  publicationContentType,
} from '~/services/publicationZip';

function fakeBucket(zip: Uint8Array) {
  const objects = new Map<string, Uint8Array>([['source', zip]]);
  const bucket = {
    async get(key: string, opts?: { range?: { offset: number; length: number } }) {
      const all = objects.get(key);
      if (!all) return null;
      const bytes = opts?.range
        ? all.slice(opts.range.offset, opts.range.offset + opts.range.length)
        : all;
      return {
        size: all.length,
        body: new Response(bytes as unknown as BodyInit).body!,
        arrayBuffer: async () =>
          bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
      };
    },
    async put(key: string, body: ReadableStream<Uint8Array>) {
      objects.set(key, new Uint8Array(await new Response(body).arrayBuffer()));
    },
    async delete(key: string) {
      objects.delete(key);
    },
  } as unknown as R2Bucket;
  return { bucket, objects };
}

async function unpack(zip: Uint8Array, cap = 25 * 1024 * 1024) {
  const { bucket, objects } = fakeBucket(zip);
  const result = await unpackPublicationZip(bucket, 'source', zip.length, 'pub-id', 1, cap);
  return { result, objects };
}

describe('publication ZIP', () => {
  it('serves Vite assets from a root index and unwraps a single report folder', async () => {
    const vite = zipSync({
      'index.html': strToU8('<script src="./assets/app.js"></script>'),
      'assets/app.js': strToU8('ok'),
    });
    const v = await unpack(vite);
    expect(v.result.entryPath).toBe('index.html');
    expect(v.result.files.map((f) => f.path)).toEqual(['index.html', 'assets/app.js']);
    expect(new TextDecoder().decode(v.objects.get('pub/pub-id/v1/assets/app.js'))).toBe('ok');
    const report = zipSync({
      'playwright-report/index.html': strToU8('<link href="./assets/style.css">'),
      'playwright-report/assets/style.css': strToU8('body{}'),
    });
    const r = await unpack(report);
    expect(r.result.files.map((f) => f.path)).toEqual(['index.html', 'assets/style.css']);
  });

  it.each([
    ['traversal', '../index.html', 'unsafe_path'],
    ['absolute', '/index.html', 'unsafe_path'],
    ['backslash', 'x\\index.html', 'unsafe_path'],
  ])('rejects %s paths', async (_label, path, code) => {
    await expect(unpack(zipSync({ [path]: strToU8('x') }))).rejects.toMatchObject({ code });
  });

  it('rejects duplicate normalized paths', async () => {
    await expect(
      unpack(zipSync({ 'index.html': strToU8('a'), './index.html': strToU8('b') })),
    ).rejects.toMatchObject({ code: 'duplicate_path' });
  });

  it('rejects more than 2000 entries and a high compression ratio', async () => {
    const many = Object.fromEntries(
      Array.from({ length: 2001 }, (_, i) => [`${i}.txt`, strToU8('x')]),
    );
    await expect(unpack(zipSync(many))).rejects.toMatchObject({ code: 'too_many_entries' });
    await expect(
      unpack(zipSync({ 'index.html': strToU8('a'.repeat(200000)) })),
    ).rejects.toMatchObject({ code: 'compression_ratio' });
  });

  it('rejects symlinks and archives without an HTML entry', async () => {
    const zip = zipSync({ 'index.html': strToU8('ok') });
    const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
    for (let i = 0; i + 46 < zip.length; i++)
      if (view.getUint32(i, true) === 0x02014b50) {
        view.setUint32(i + 38, 0o120777 << 16, true);
        break;
      }
    await expect(unpack(zip)).rejects.toMatchObject({ code: 'unsafe_entry' });
    await expect(unpack(zipSync({ 'README.txt': strToU8('x') }))).rejects.toMatchObject({
      code: 'no_entry',
    });
  });

  it('serves unknown extensions as attachments', () => {
    expect(publicationContentType('data.xyz')).toBe('application/octet-stream');
  });
});
