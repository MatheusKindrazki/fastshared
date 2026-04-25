import { Readable } from 'node:stream';
import { mkdtemp, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { describe, expect, it } from 'vitest';
import { detectMime, stageInputs } from '../src/stage.js';

describe('stageInputs', () => {
  it('stages a regular file with sha256 and mime detection', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-stage-file-'));
    const file = join(dir, 'hello.txt');
    await writeFile(file, 'hello world');

    const staged = await stageInputs([file], { cwd: dir });
    expect(staged.filename).toBe('hello.txt');
    expect(staged.contentType).toBe('text/plain');
    expect(staged.sizeBytes).toBe(11);
    expect(staged.sha256).toBe(
      'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9',
    );
    await staged.cleanup();
  });

  it('writes stdin to a temporary file and cleans it up', async () => {
    const staged = await stageInputs(['-'], {
      name: 'output.bin',
      stdin: Readable.from(['abc']),
    });

    expect(staged.filename).toBe('output.bin');
    expect(staged.contentType).toBe('application/octet-stream');
    expect(await readFile(staged.filePath, 'utf8')).toBe('abc');
    await staged.cleanup();
    await expect(stat(staged.filePath)).rejects.toMatchObject({ code: 'ENOENT' });
  });

  it('zips directories for a single share URL', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-stage-dir-'));
    const folder = join(dir, 'bundle');
    await mkdir(join(folder, 'nested'), { recursive: true });
    await writeFile(join(folder, 'nested', 'a.txt'), 'A');
    await writeFile(join(folder, 'b.json'), '{"b":true}');

    const staged = await stageInputs([folder], { cwd: dir });
    expect(staged.filename).toBe('bundle.zip');
    expect(staged.contentType).toBe('application/zip');
    expect(staged.sourceKind).toBe('zip');
    expect((await readFile(staged.filePath)).subarray(0, 4).toString('hex')).toBe('504b0304');
    await staged.cleanup();
  });
});

describe('detectMime', () => {
  it('falls back to application/octet-stream', () => {
    expect(detectMime('artifact.unknownext')).toBe('application/octet-stream');
  });
});
