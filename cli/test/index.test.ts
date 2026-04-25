import { mkdir, mkdtemp, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { describe, expect, it } from 'vitest';
import { isMainModule } from '../src/index.js';

describe('entrypoint detection', () => {
  it('recognizes the CLI when invoked through an installer symlink', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-entrypoint-'));
    const entry = join(dir, 'dist', 'index.js');
    const bin = join(dir, 'bin', 'fastshared');
    await mkdir(join(dir, 'dist'), { recursive: true });
    await mkdir(join(dir, 'bin'), { recursive: true });
    await writeFile(entry, '#!/usr/bin/env node\n');
    await symlink(entry, bin);

    expect(isMainModule(pathToFileURL(entry).href, bin)).toBe(true);
  });
});
