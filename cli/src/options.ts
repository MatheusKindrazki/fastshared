export const CLI_VERSION = '0.1.1';
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

export interface CommandFlags {
  outputJson: boolean;
  quiet: boolean;
  help: boolean;
  version: boolean;
  apiUrl?: string;
  configPath?: string;
}

export type ParsedCommand =
  | ({ command: 'upload' } & ParsedArgs)
  | ({
      command: 'publish';
      path?: string;
      title?: string;
      update?: string;
    } & CommandFlags)
  | ({
      command: 'publications';
      action?: 'list' | 'revoke' | 'opens';
      target?: string;
    } & CommandFlags)
  | ({ command: 'mcp' } & CommandFlags)
  | ({ command: 'login'; code?: string } & CommandFlags)
  | ({ command: 'whoami' } & CommandFlags);

const SUBCOMMANDS = new Set(['publish', 'publications', 'mcp', 'login', 'whoami']);

export function parseCommand(argv: string[]): ParsedCommand {
  const { consumed, rest } = peelLeadingGlobals(argv);
  const head = rest[0];
  if (head && SUBCOMMANDS.has(head)) {
    const flags = consumeFlags([...consumed, ...rest.slice(1)], {
      title: head === 'publish',
      update: head === 'publish',
    });
    return buildSubcommand(head, flags);
  }
  return { command: 'upload', ...parseArgs(argv) };
}

export function usage(): string {
  return `Usage: fastshared [options] <file|directory|-> [...]
       fastshared publish <file|directory> [--title <text>] [--update <id|slug>]
       fastshared publications list
       fastshared publications revoke <id|slug>
       fastshared publications opens <id|slug>
       fastshared mcp
       fastshared login <code>
       fastshared whoami

Uploads a file to FastShared and prints the temporary URL.
login links this CLI to your FastShared account with the 6-digit code from
the app (Settings → Link a computer), so open alerts reach your iPhone.
publish, publications, and mcp require the publications API.

Options:
  --ttl 60s|1h|1d|1w|30d  Link lifetime for temporary uploads (default: 1h)
  --json                  Print structured JSON instead of text
  --quiet                 Suppress progress logs on stderr
  --api-url <url>          Override API URL (default: ${DEFAULT_API_URL})
  --config <path>          Override config path
  --name <filename>        Filename for stdin or generated archive
  --title <text>           Title for a publication
  --update <id|slug>       Replace a publication and keep its URL
  --version               Print CLI version
  -h, --help              Show this help
`;
}

interface FlagState extends CommandFlags {
  title?: string;
  update?: string;
  positionals: string[];
}

function peelLeadingGlobals(argv: string[]): { consumed: string[]; rest: string[] } {
  const consumed: string[] = [];
  let index = 0;
  while (index < argv.length) {
    const arg = argv[index]!;
    if (arg === '--json' || arg === '--quiet' || arg === '--help' || arg === '-h' || arg === '--version') {
      consumed.push(arg);
      index += 1;
      continue;
    }
    if (arg.startsWith('--api-url=') || arg.startsWith('--config=')) {
      consumed.push(arg);
      index += 1;
      continue;
    }
    if (arg === '--api-url' || arg === '--config') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) break;
      consumed.push(arg, value);
      index += 2;
      continue;
    }
    break;
  }
  return { consumed, rest: argv.slice(index) };
}

function consumeFlags(args: string[], allowed: { title: boolean; update: boolean }): FlagState {
  const state: FlagState = {
    outputJson: false,
    quiet: false,
    help: false,
    version: false,
    positionals: [],
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]!;
    if (arg === '--') {
      state.positionals.push(...args.slice(index + 1));
      break;
    }
    if (arg === '--json') {
      state.outputJson = true;
      continue;
    }
    if (arg === '--quiet') {
      state.quiet = true;
      continue;
    }
    if (arg === '-h' || arg === '--help') {
      state.help = true;
      continue;
    }
    if (arg === '--version') {
      state.version = true;
      continue;
    }
    if (arg === '--api-url' || arg.startsWith('--api-url=')) {
      state.apiUrl = stripTrailingSlash(flagValue(arg, args, index, '--api-url'));
      if (arg === '--api-url') index += 1;
      continue;
    }
    if (arg === '--config' || arg.startsWith('--config=')) {
      state.configPath = flagValue(arg, args, index, '--config');
      if (arg === '--config') index += 1;
      continue;
    }
    if (allowed.title && (arg === '--title' || arg.startsWith('--title='))) {
      state.title = flagValue(arg, args, index, '--title');
      if (arg === '--title') index += 1;
      continue;
    }
    if (allowed.update && (arg === '--update' || arg.startsWith('--update='))) {
      state.update = flagValue(arg, args, index, '--update');
      if (arg === '--update') index += 1;
      continue;
    }
    if (arg.startsWith('--')) throw new UsageError(`unknown option: ${arg}`);
    state.positionals.push(arg);
  }
  return state;
}

function buildSubcommand(head: string, state: FlagState): ParsedCommand {
  const flags = commandFlags(state);
  if (head === 'login') {
    const code = state.positionals[0];
    if (!state.help && !state.version) {
      if (state.positionals.length !== 1 || !code || !/^\d{6}$/.test(code)) {
        throw new UsageError('login expects the 6-digit code from the app. Usage: fastshared login 123456');
      }
    }
    return { command: 'login', ...flags, ...(code ? { code } : {}) };
  }
  if (head === 'whoami') {
    if (!state.help && !state.version && state.positionals.length > 0) {
      throw new UsageError('whoami does not take arguments.');
    }
    return { command: 'whoami', ...flags };
  }
  if (head === 'mcp') {
    if (!state.help && !state.version && state.positionals.length > 0) {
      throw new UsageError('mcp does not take a path. Usage: fastshared mcp');
    }
    return { command: 'mcp', ...flags };
  }
  if (head === 'publish') {
    const pathArg = state.positionals[0];
    if (!state.help && !state.version) {
      if (state.positionals.length !== 1) throw new UsageError('publish expects one file or directory.');
      if (pathArg === '-') throw new UsageError('publish reads a file or directory, not stdin.');
    }
    if (state.update && (state.update.includes('/') || state.update.includes('\\'))) {
      throw new UsageError('publication id or slug cannot contain a slash.');
    }
    return {
      command: 'publish',
      ...flags,
      ...(pathArg && pathArg !== '-' ? { path: pathArg } : {}),
      ...(state.title ? { title: state.title } : {}),
      ...(state.update ? { update: state.update } : {}),
    };
  }
  const action = state.positionals[0];
  const target = state.positionals[1];
  if (!state.help && !state.version) {
    if (action !== 'list' && action !== 'revoke' && action !== 'opens') {
      throw new UsageError('publications expects list, revoke <id|slug>, or opens <id|slug>.');
    }
    if (action === 'list' && state.positionals.length !== 1) {
      throw new UsageError('publications list does not take an id.');
    }
    if ((action === 'revoke' || action === 'opens') && state.positionals.length !== 2) {
      throw new UsageError(`publications ${action} expects one id or slug.`);
    }
    if (target && (target.includes('/') || target.includes('\\'))) {
      throw new UsageError('publication id or slug cannot contain a slash.');
    }
  }
  return {
    command: 'publications',
    ...flags,
    ...(action === 'list' || action === 'revoke' || action === 'opens' ? { action } : {}),
    ...(target ? { target } : {}),
  };
}

function commandFlags(state: FlagState): CommandFlags {
  return {
    outputJson: state.outputJson,
    quiet: state.quiet,
    help: state.help,
    version: state.version,
    ...(state.apiUrl ? { apiUrl: state.apiUrl } : {}),
    ...(state.configPath ? { configPath: state.configPath } : {}),
  };
}

function flagValue(arg: string, args: string[], index: number, flag: string): string {
  if (arg.startsWith(`${flag}=`)) return arg.slice(flag.length + 1);
  return readValue(args, index + 1, flag);
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
