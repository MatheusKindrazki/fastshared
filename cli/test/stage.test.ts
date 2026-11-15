import { Readable } from 'node:stream';
import { mkdtemp, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { describe, expect, it } from 'vitest';
import { detectMime, stageArchiveFiles, stageInputs } from '../src/stage.js';

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

describe('stageArchiveFiles', () => {
  it('stores a single HTML file under index.html', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-stage-html-'));
    const file = join(dir, 'page.html');
    await writeFile(file, '<h1>Hi</h1>');

    const staged = await stageArchiveFiles([{ fsPath: file, archivePath: 'index.html' }], 'page.zip');
    const bytes = await readFile(staged.filePath);
    expect(staged.filename).toBe('page.zip');
    expect(staged.contentType).toBe('application/zip');
    expect(bytes.includes(Buffer.from('index.html'))).toBe(true);
    expect(bytes.includes(Buffer.from('<h1>Hi</h1>'))).toBe(true);
    await staged.cleanup();
  });
});

describe('detectMime', () => {
  it('falls back to application/octet-stream', () => {
    expect(detectMime('artifact.unknownext')).toBe('application/octet-stream');
  });

  it('sends HTML as text/html so recipients see the page instead of a download', () => {
    expect(detectMime('report.html')).toBe('text/html');
    expect(detectMime('REPORT.HTM')).toBe('text/html');
  });

  it('maps common log, video, image and audio extensions', () => {
    expect(detectMime('build.log')).toBe('text/plain');
    expect(detectMime('demo.webm')).toBe('video/webm');
    expect(detectMime('photo.heic')).toBe('image/heic');
    expect(detectMime('voice.m4a')).toBe('audio/mp4');
  });
});
