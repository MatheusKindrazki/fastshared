#!/usr/bin/env node
import { copyFile, mkdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const outDir = 'dist-release';
await rm(outDir, { recursive: true, force: true });
await mkdir(outDir, { recursive: true });

const packed = spawnSync('npm', ['pack', '--pack-destination', outDir], {
  encoding: 'utf8',
  stdio: ['ignore', 'pipe', 'inherit'],
});

if (packed.status !== 0) {
  process.exit(packed.status ?? 1);
}

const file = packed.stdout.trim().split(/\r?\n/).filter(Boolean).pop();
if (!file) {
  throw new Error('npm pack did not report an output filename');
}

await copyFile(join(outDir, file), join(outDir, 'fastshared-cli.tgz'));
console.log(join(outDir, 'fastshared-cli.tgz'));
