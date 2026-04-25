#!/usr/bin/env node
import { pathToFileURL } from 'node:url';
import { runCli } from './cli.js';

const entry = process.argv[1] ? pathToFileURL(process.argv[1]).href : '';

if (import.meta.url === entry) {
  runCli(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err: unknown) => {
      process.stderr.write(`fastshared: ${err instanceof Error ? err.message : String(err)}\n`);
      process.exitCode = 1;
    });
}

export { runCli } from './cli.js';
export { parseArgs, parseTtl } from './options.js';
export { loadConfig, resolveConfigPath, saveConfig } from './config.js';
export { stageInputs, sha256File, detectMime } from './stage.js';
