import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import {
  lstat,
  mkdir,
  mkdtemp,
  open,
  readdir,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path, { basename, dirname, join, relative } from 'node:path';
import { pipeline } from 'node:stream/promises';
import type { Readable } from 'node:stream';

export interface StagedUpload {
  filePath: string;
  filename: string;
  contentType: string;
  sizeBytes: number;
  sha256: string;
  sourceKind: 'file' | 'stdin' | 'zip';
  cleanup: () => Promise<void>;
}

export interface StageOptions {
  name?: string;
  stdin?: NodeJS.ReadableStream;
  cwd?: string;
}

interface ZipEntry {
  fsPath: string;
  archivePath: string;
  size: number;
  crc32: number;
  localHeaderOffset: number;
  dosTime: number;
  dosDate: number;
}

export async function stageInputs(inputs: string[], options: StageOptions = {}): Promise<StagedUpload> {
  const cwd = options.cwd ?? process.cwd();
  if (inputs.length === 1 && inputs[0] === '-') {
    return stageStdin(options.stdin ?? process.stdin, options.name ?? 'stdin.bin');
  }

  const resolved = inputs.map((input) => path.resolve(cwd, input));
  const stats = await Promise.all(resolved.map((input) => lstat(input)));
  const singleFile = resolved.length === 1 && stats[0]?.isFile() === true;
  if (singleFile) {
    const filePath = resolved[0]!;
    const filename = options.name ?? basename(filePath);
    const st = await stat(filePath);
    return {
      filePath,
      filename,
      contentType: detectMime(filename),
      sizeBytes: st.size,
      sha256: await sha256File(filePath),
      sourceKind: 'file',
      cleanup: async () => undefined,
    };
  }

  return stageZip(resolved, stats, cwd, options.name);
}

export function detectMime(filename: string): string {
  const ext = filename.toLowerCase().split('.').pop() ?? '';
  const map: Record<string, string> = {
    txt: 'text/plain',
    md: 'text/markdown',
    csv: 'text/csv',
    json: 'application/json',
    xml: 'application/xml',
    yaml: 'application/yaml',
    yml: 'application/yaml',
    pdf: 'application/pdf',
    zip: 'application/zip',
    png: 'image/png',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    gif: 'image/gif',
    webp: 'image/webp',
    svg: 'image/svg+xml',
    mp4: 'video/mp4',
    mov: 'video/quicktime',
    mp3: 'audio/mpeg',
    wav: 'audio/wav',
  };
  return map[ext] ?? 'application/octet-stream';
}

async function stageStdin(stdin: NodeJS.ReadableStream, filename: string): Promise<StagedUpload> {
  const tempDir = await mkdtemp(join(tmpdir(), 'fastshared-'));
  const filePath = join(tempDir, basename(filename));
  await pipeline(stdin, await openWriteStream(filePath));
  const st = await stat(filePath);
  return {
    filePath,
    filename,
    contentType: detectMime(filename),
    sizeBytes: st.size,
    sha256: await sha256File(filePath),
    sourceKind: 'stdin',
    cleanup: async () => {
      await rm(tempDir, { recursive: true, force: true });
    },
  };
}

async function stageZip(
  inputs: string[],
  stats: Array<Awaited<ReturnType<typeof lstat>>>,
  cwd: string,
  overrideName: string | undefined,
): Promise<StagedUpload> {
  const tempDir = await mkdtemp(join(tmpdir(), 'fastshared-'));
  const filename = overrideName ?? defaultZipName(inputs, stats, cwd);
  const safeName = filename.toLowerCase().endsWith('.zip') ? filename : `${filename}.zip`;
  const filePath = join(tempDir, basename(safeName));
  await createZipArchive(inputs, stats, cwd, filePath);
  const st = await stat(filePath);
  return {
    filePath,
    filename: basename(safeName),
    contentType: 'application/zip',
    sizeBytes: st.size,
    sha256: await sha256File(filePath),
    sourceKind: 'zip',
    cleanup: async () => {
      await rm(tempDir, { recursive: true, force: true });
    },
  };
}

function defaultZipName(
  inputs: string[],
  stats: Array<Awaited<ReturnType<typeof lstat>>>,
  cwd: string,
): string {
  if (inputs.length === 1 && stats[0]?.isDirectory()) return `${basename(inputs[0]!)}.zip`;
  const cwdName = basename(cwd) || 'bundle';
  return `${cwdName}-fastshared.zip`;
}

async function openWriteStream(filePath: string) {
  const handle = await open(filePath, 'w', 0o600);
  return handle.createWriteStream();
}

export async function sha256File(filePath: string): Promise<string> {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(filePath)) {
    hash.update(chunk as Buffer);
  }
  return hash.digest('hex');
}

async function createZipArchive(
  inputs: string[],
  stats: Array<Awaited<ReturnType<typeof lstat>>>,
  cwd: string,
  outputPath: string,
): Promise<void> {
  const files = await collectFiles(inputs, stats, cwd);
  if (files.length === 0) throw new Error('no files found to archive');

  const entries: ZipEntry[] = [];
  for (const file of files) {
    const st = await stat(file.fsPath);
    if (st.size > 0xffffffff) {
      throw new Error(`file too large for zip64-less archive: ${file.fsPath}`);
    }
    const { dosTime, dosDate } = dateToDos(st.mtime);
    entries.push({
      fsPath: file.fsPath,
      archivePath: file.archivePath,
      size: st.size,
      crc32: await crc32File(file.fsPath),
      localHeaderOffset: 0,
      dosTime,
      dosDate,
    });
  }

  const handle = await open(outputPath, 'w', 0o600);
  let offset = 0;
  try {
    for (const entry of entries) {
      entry.localHeaderOffset = offset;
      const name = Buffer.from(entry.archivePath, 'utf8');
      const header = Buffer.alloc(30);
      header.writeUInt32LE(0x04034b50, 0);
      header.writeUInt16LE(20, 4);
      header.writeUInt16LE(0, 6);
      header.writeUInt16LE(0, 8);
      header.writeUInt16LE(entry.dosTime, 10);
      header.writeUInt16LE(entry.dosDate, 12);
      header.writeUInt32LE(entry.crc32, 14);
      header.writeUInt32LE(entry.size, 18);
      header.writeUInt32LE(entry.size, 22);
      header.writeUInt16LE(name.length, 26);
      header.writeUInt16LE(0, 28);
      await handle.write(header);
      await handle.write(name);
      offset += header.length + name.length;
      for await (const chunk of createReadStream(entry.fsPath)) {
        const buf = chunk as Buffer;
        await handle.write(buf);
        offset += buf.length;
      }
    }

    const centralStart = offset;
    for (const entry of entries) {
      const name = Buffer.from(entry.archivePath, 'utf8');
      const central = Buffer.alloc(46);
      central.writeUInt32LE(0x02014b50, 0);
      central.writeUInt16LE(20, 4);
      central.writeUInt16LE(20, 6);
      central.writeUInt16LE(0, 8);
      central.writeUInt16LE(0, 10);
      central.writeUInt16LE(entry.dosTime, 12);
      central.writeUInt16LE(entry.dosDate, 14);
      central.writeUInt32LE(entry.crc32, 16);
      central.writeUInt32LE(entry.size, 20);
      central.writeUInt32LE(entry.size, 24);
      central.writeUInt16LE(name.length, 28);
      central.writeUInt16LE(0, 30);
      central.writeUInt16LE(0, 32);
      central.writeUInt16LE(0, 34);
      central.writeUInt16LE(0, 36);
      central.writeUInt32LE(0, 38);
      central.writeUInt32LE(entry.localHeaderOffset, 42);
      await handle.write(central);
      await handle.write(name);
      offset += central.length + name.length;
    }
    const centralSize = offset - centralStart;
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(0, 4);
    end.writeUInt16LE(0, 6);
    end.writeUInt16LE(entries.length, 8);
    end.writeUInt16LE(entries.length, 10);
    end.writeUInt32LE(centralSize, 12);
    end.writeUInt32LE(centralStart, 16);
    end.writeUInt16LE(0, 20);
    await handle.write(end);
  } finally {
    await handle.close();
  }
}

async function collectFiles(
  inputs: string[],
  stats: Array<Awaited<ReturnType<typeof lstat>>>,
  cwd: string,
): Promise<Array<{ fsPath: string; archivePath: string }>> {
  const out: Array<{ fsPath: string; archivePath: string }> = [];
  for (let i = 0; i < inputs.length; i += 1) {
    const input = inputs[i]!;
    const st = stats[i]!;
    if (st.isDirectory()) {
      const root = basename(input);
      const children = await walkDirectory(input);
      for (const child of children) {
        out.push({
          fsPath: child,
          archivePath: sanitizeArchivePath(path.posix.join(root, toPosix(relative(input, child)))),
        });
      }
    } else if (st.isFile()) {
      const rel = toPosix(relative(cwd, input));
      out.push({ fsPath: input, archivePath: sanitizeArchivePath(rel || basename(input)) });
    }
  }
  out.sort((a, b) => a.archivePath.localeCompare(b.archivePath));
  return out;
}

async function walkDirectory(root: string): Promise<string[]> {
  const entries = await readdir(root, { withFileTypes: true });
  const out: string[] = [];
  for (const entry of entries) {
    const full = join(root, entry.name);
    if (entry.isDirectory()) out.push(...(await walkDirectory(full)));
    else if (entry.isFile()) out.push(full);
  }
  return out;
}

function sanitizeArchivePath(value: string): string {
  const normalized = path.posix.normalize(toPosix(value)).replace(/^(\.\.\/)+/, '').replace(/^\/+/, '');
  return normalized === '.' || normalized.length === 0 ? 'file' : normalized;
}

function toPosix(value: string): string {
  return value.split(path.sep).join('/');
}

function dateToDos(date: Date): { dosTime: number; dosDate: number } {
  const year = Math.max(1980, date.getFullYear());
  const dosTime = (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2);
  const dosDate = ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
  return { dosTime, dosDate };
}

const CRC_TABLE = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

async function crc32File(filePath: string): Promise<number> {
  let crc = 0xffffffff;
  for await (const chunk of createReadStream(filePath)) {
    const buf = chunk as Buffer;
    for (const byte of buf) {
      crc = CRC_TABLE[(crc ^ byte) & 0xff]! ^ (crc >>> 8);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}
