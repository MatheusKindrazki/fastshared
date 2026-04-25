#!/usr/bin/env node
import { realpathSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { runCli } from './cli.js';

if (isMainModule(import.meta.url)) {
  runCli(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err: unknown) => {
      process.stderr.write(`fastshared: ${err instanceof Error ? err.message : String(err)}\n`);
      process.exitCode = 1;
    });
}

export function isMainModule(importMetaUrl: string, argv1 = process.argv[1]): boolean {
  if (!argv1) return false;
  try {
    return realpathSync(fileURLToPath(importMetaUrl)) === realpathSync(argv1);
  } catch {
    return importMetaUrl === pathToFileURL(argv1).href;
  }
}

export { runCli } from './cli.js';
export { parseArgs, parseTtl } from './options.js';
export { loadConfig, resolveConfigPath, saveConfig } from './config.js';
export { stageInputs, sha256File, detectMime } from './stage.js';
