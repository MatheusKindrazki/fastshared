#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';

const configPath = new URL('../wrangler.toml', import.meta.url);
const config = readFileSync(configPath, 'utf8');
const dryRun = process.argv.includes('--dry-run');
const namespaceTitle = process.env.FASTSHARED_STAGING_RATE_LIMIT_KV_TITLE ?? 'fastshared-api-stg-RATE_LIMIT';
const accountId =
  process.env.FASTSHARED_CLOUDFLARE_ACCOUNT_ID ??
  matchRequired(config, /^account_id\s*=\s*"([^"]+)"/m, 'account_id');
const apiToken = process.env.CLOUDFLARE_API_TOKEN;

if (!apiToken && !dryRun) {
  fail('CLOUDFLARE_API_TOKEN is required to ensure the staging RATE_LIMIT KV namespace');
}

const namespaceId = dryRun
  ? '11111111111111111111111111111111'
  : await ensureNamespace({ accountId, apiToken, title: namespaceTitle });

const updated = patchStagingRateLimitNamespace(config, namespaceId);
if (updated !== config && !dryRun) {
  writeFileSync(configPath, updated);
}

console.log(
  dryRun
    ? `Dry run OK: would bind ${namespaceTitle} (${namespaceId}) in wrangler.toml`
    : `Bound ${namespaceTitle} (${namespaceId}) in wrangler.toml`,
);

async function ensureNamespace({ accountId, apiToken, title }) {
  const existing = await findNamespace({ accountId, apiToken, title });
  if (existing) return existing.id;

  const created = await cloudflareFetch({
    accountId,
    apiToken,
    path: '/storage/kv/namespaces',
    init: {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ title }),
    },
  });
  if (!created.result?.id) {
    fail(`Cloudflare did not return an id for new KV namespace '${title}'`);
  }
  return created.result.id;
}

async function findNamespace({ accountId, apiToken, title }) {
  let page = 1;
  for (;;) {
    const data = await cloudflareFetch({
      accountId,
      apiToken,
      path: `/storage/kv/namespaces?per_page=100&page=${page}`,
    });
    const found = (data.result ?? []).find((namespace) => namespace.title === title);
    if (found) return found;

    const info = data.result_info;
    if (!info || page >= info.total_pages) return null;
    page += 1;
  }
}

async function cloudflareFetch({ accountId, apiToken, path, init = {} }) {
  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${apiToken}`,
      ...(init.headers ?? {}),
    },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.success === false) {
    const message = (data.errors ?? [])
      .map((err) => `${err.code ?? 'unknown'}: ${err.message ?? 'unknown error'}`)
      .join('; ');
    fail(`Cloudflare API request failed for ${path}: ${message || response.statusText}`);
  }
  return data;
}

function patchStagingRateLimitNamespace(source, namespaceId) {
  const blockPattern =
    /(\[\[env\.staging\.kv_namespaces\]\]\s*binding\s*=\s*"RATE_LIMIT"\s*id\s*=\s*")([^"]*)(")/m;
  if (!blockPattern.test(source)) {
    fail('Could not find env.staging RATE_LIMIT KV namespace binding in wrangler.toml');
  }
  return source.replace(blockPattern, `$1${namespaceId}$3`);
}

function matchRequired(source, pattern, label) {
  const match = source.match(pattern);
  if (!match?.[1]) fail(`Could not find ${label} in wrangler.toml`);
  return match[1];
}

function fail(message) {
  console.error(`ensure-staging-rate-limit-kv: ${message}`);
  process.exit(1);
}
