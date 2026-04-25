export const CLI_VERSION = '0.1.0';
export const DEFAULT_API_URL = 'https://api.fastsha.red';

export type RetentionPolicy = 'oneMinute' | 'oneHour' | 'oneDay' | 'oneWeek' | 'oneMonth';

export interface ParsedArgs {
  inputs: string[];
  retentionPolicy: RetentionPolicy;
  outputJson: boolean;
  quiet: boolean;
  help: boolean;
  version: boolean;
  apiUrl?: string;
  configPath?: string;
  name?: string;
}

export class UsageError extends Error {
  readonly exitCode = 2;
}

export function parseTtl(raw: string | undefined): RetentionPolicy {
  const value = (raw ?? '1h').trim().toLowerCase();
  switch (value) {
    case '60s':
    case '1m':
    case 'one-minute':
    case 'oneminute':
      return 'oneMinute';
    case '1h':
    case '60m':
    case 'one-hour':
    case 'onehour':
      return 'oneHour';
    case '1d':
    case '24h':
    case 'one-day':
    case 'oneday':
      return 'oneDay';
    case '1w':
    case '7d':
    case 'one-week':
    case 'oneweek':
      return 'oneWeek';
    case '30d':
    case '1mo':
    case 'one-month':
    case 'onemonth':
      return 'oneMonth';
    default:
      throw new UsageError(`invalid --ttl "${raw}". Use 60s, 1h, 1d, 1w, or 30d.`);
  }
}

export function parseArgs(argv: string[]): ParsedArgs {
  const args = argv[0] === 'upload' ? argv.slice(1) : argv.slice();
  const inputs: string[] = [];
  let ttl: string | undefined;
  let outputJson = false;
  let quiet = false;
  let help = false;
  let version = false;
  let apiUrl: string | undefined;
  let configPath: string | undefined;
  let name: string | undefined;

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i]!;
    if (arg === '--') {
      inputs.push(...args.slice(i + 1));
      break;
    }
    if (arg === '-h' || arg === '--help') {
      help = true;
      continue;
    }
    if (arg === '--version') {
      version = true;
      continue;
    }
    if (arg === '--json') {
      outputJson = true;
      continue;
    }
    if (arg === '--quiet') {
      quiet = true;
      continue;
    }
    if (arg.startsWith('--ttl=')) {
      ttl = arg.slice('--ttl='.length);
      continue;
    }
    if (arg === '--ttl') {
      ttl = readValue(args, ++i, '--ttl');
      continue;
    }
    if (arg.startsWith('--api-url=')) {
      apiUrl = arg.slice('--api-url='.length);
      continue;
    }
    if (arg === '--api-url') {
      apiUrl = readValue(args, ++i, '--api-url');
      continue;
    }
    if (arg.startsWith('--config=')) {
      configPath = arg.slice('--config='.length);
      continue;
    }
    if (arg === '--config') {
      configPath = readValue(args, ++i, '--config');
      continue;
    }
    if (arg.startsWith('--name=')) {
      name = arg.slice('--name='.length);
      continue;
    }
    if (arg === '--name') {
      name = readValue(args, ++i, '--name');
      continue;
    }
    if (arg.startsWith('--')) {
      throw new UsageError(`unknown option: ${arg}`);
    }
    inputs.push(arg);
  }

  if (!help && !version && inputs.length === 0) {
    throw new UsageError('missing input file, directory, or "-".');
  }

  return {
    inputs,
    retentionPolicy: parseTtl(ttl),
    outputJson,
    quiet,
    help,
    version,
    ...(apiUrl ? { apiUrl: stripTrailingSlash(apiUrl) } : {}),
    ...(configPath ? { configPath } : {}),
    ...(name ? { name } : {}),
  };
}

export function usage(): string {
  return `Usage: fastshared [options] <file|directory|-> [...]

Uploads a file to FastShared and prints the temporary URL.

Options:
  --ttl 60s|1h|1d|1w|30d  Link lifetime (default: 1h)
  --json                  Print structured JSON instead of the URL only
  --quiet                 Suppress progress logs on stderr
  --api-url <url>          Override API URL (default: ${DEFAULT_API_URL})
  --config <path>          Override config path
  --name <filename>        Filename for stdin or generated archive
  --version               Print CLI version
  -h, --help              Show this help
`;
}

function readValue(args: string[], index: number, flag: string): string {
  const value = args[index];
  if (!value || value.startsWith('--')) {
    throw new UsageError(`${flag} requires a value.`);
  }
  return value;
}

function stripTrailingSlash(value: string): string {
  return value.replace(/\/+$/, '');
}
