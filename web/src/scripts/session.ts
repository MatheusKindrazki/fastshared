export const TOKEN_KEY = 'fs-web-token';

export const UNPACK_MESSAGES: Record<string, string> = {
  compression_ratio: 'This archive is too compressed to publish. Export it again with normal compression.',
  duplicate_path: 'This archive contains two files at the same path. Remove the duplicate and try again.',
  file_too_large: 'One file inside the archive is over the size limit.',
  invalid_zip: 'This file is not a valid ZIP archive.',
  no_entry: 'Add an index.html, or a single HTML file, at the top of the archive.',
  too_many_entries: 'This archive has too many files. Split the project and try again.',
  total_too_large: 'Unpacked, this archive is over the size limit.',
  unsafe_entry: 'This archive contains a file type we cannot publish.',
  unsafe_path: 'This archive contains a path we cannot publish. Use relative paths only.',
};

export type ProblemBody = {
  code?: string;
  title?: string;
  detail?: string;
  unpack_error?: string;
  upgradeUrl?: string;
};

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly unpackError: string | undefined;
  readonly upgradeUrl: string | undefined;

  constructor(
    message: string,
    status: number,
    code: string,
    extra?: { unpackError?: string; upgradeUrl?: string },
  ) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.unpackError = extra?.unpackError;
    this.upgradeUrl = extra?.upgradeUrl;
  }
}

export type MeResponse = {
  isPro?: boolean;
  tier?: string;
  userId?: string;
  user?: { id?: string };
};

export type BillingConfig = {
  clientToken?: string;
  environment?: string;
  priceIds?: Record<string, string>;
};

export type PublicationSummary = {
  id: string;
  slug: string;
  url: string | null;
  title: string | null;
  status: string;
  currentVersion: number | null;
  expires_at: string | null;
  opensLast7Days: number;
};

export function apiBase(): string {
  const raw = import.meta.env.PUBLIC_API_BASE || 'https://api.fastsha.red';
  return raw.replace(/\/$/, '');
}

export function readToken(): string | null {
  try {
    const value = localStorage.getItem(TOKEN_KEY);
    return value && value.length > 0 ? value : null;
  } catch {
    return null;
  }
}

export function writeToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
}

/** Stores `#token=` and removes the fragment so the token does not stay in the URL. */
export function consumeHashToken(): string | null {
  const hash = location.hash.startsWith('#') ? location.hash.slice(1) : '';
  if (hash.length > 0) {
    const token = new URLSearchParams(hash).get('token');
    if (token && token.length > 0) {
      writeToken(token);
      history.replaceState(null, '', location.pathname + location.search);
      return token;
    }
  }
  return readToken();
}

function safeUpgradeUrl(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  if (value.startsWith('/') && !value.startsWith('//')) return value;
  try {
    const url = new URL(value);
    if (url.protocol === 'https:' || url.protocol === 'http:') return url.toString();
  } catch {
    return undefined;
  }
  return undefined;
}

async function toError(res: Response): Promise<ApiError> {
  let body: ProblemBody = {};
  try {
    body = (await res.json()) as ProblemBody;
  } catch {
    body = {};
  }
  const unpack = typeof body.unpack_error === 'string' ? body.unpack_error : undefined;
  const code = typeof body.code === 'string' ? body.code : 'request_failed';
  const message =
    (unpack && UNPACK_MESSAGES[unpack]) ||
    (code === 'publication_limit' && 'The free publication limit is reached.') ||
    (code === 'account_required' && 'Publishing on Pro needs a signed-in account.') ||
    (code === 'upload_too_large' && 'This file is over the upload limit.') ||
    (code === 'storage_limit' && 'This account is over the storage limit.') ||
    (code === 'upload_incomplete' && 'The upload did not finish. Try again.') ||
    (code === 'invalid_publication' && 'This publication could not be created. Check the file and try again.') ||
    (code === 'publication_host_unavailable' && 'Publishing is temporarily unavailable.') ||
    (res.status === 401 && 'Sign in again.') ||
    'The request did not succeed. Try again.';
  return new ApiError(message, res.status, code, {
    unpackError: unpack,
    upgradeUrl: safeUpgradeUrl(body.upgradeUrl),
  });
}

export async function apiSend(
  path: string,
  init: { method?: string; token?: string | null; body?: unknown } = {},
): Promise<Response> {
  const headers = new Headers({ Accept: 'application/json' });
  if (init.token) headers.set('Authorization', `Bearer ${init.token}`);
  if (init.body !== undefined) headers.set('Content-Type', 'application/json');
  return fetch(`${apiBase()}${path}`, {
    method: init.method ?? 'GET',
    headers,
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
}

export async function apiJson<T>(
  path: string,
  init: { method?: string; token?: string | null; body?: unknown } = {},
): Promise<T> {
  const res = await apiSend(path, init);
  if (!res.ok) throw await toError(res);
  if (res.status === 204 || res.status === 202) return undefined as T;
  const text = await res.text();
  if (!text) return undefined as T;
  return JSON.parse(text) as T;
}

// Pairs this browser with the account of the FastShared app on iPhone, iPad or
// Mac: the app shows a 6-digit code, the browser registers itself as a web
// device and redeems the code. No email or password involved.
export async function linkWithAppCode(code: string): Promise<void> {
  if (!/^\d{6}$/.test(code)) {
    throw new ApiError('Enter the 6-digit code from the app.', 400, 'invalid_code');
  }
  let token = readToken();
  if (!token) {
    const registered = await apiJson<{ deviceToken: string }>('/v1/devices', {
      method: 'POST',
      body: { platform: 'web', appVersion: 'web' },
    });
    token = registered.deviceToken;
    writeToken(token);
  }
  try {
    await apiJson('/v1/link-codes/claim', { method: 'POST', token, body: { code } });
  } catch (error) {
    if (error instanceof ApiError && error.status === 409) throw error;
    throw error instanceof ApiError && error.status === 400
      ? new ApiError('That code is invalid or expired. Get a new one in the app.', 400, 'invalid_code')
      : error;
  }
}

export async function startEmailLogin(email: string): Promise<void> {
  let res: Response;
  try {
    res = await apiSend('/v1/auth/email/start', { method: 'POST', body: { email } });
  } catch {
    throw new ApiError('The sign-in email could not be sent. Try again.', 0, 'network');
  }
  if (res.status === 202 || res.ok) return;
  throw await toError(res);
}

export function userIdFromMe(me: MeResponse): string | null {
  if (typeof me.userId === 'string' && me.userId.length > 0) return me.userId;
  if (typeof me.user?.id === 'string' && me.user.id.length > 0) return me.user.id;
  return null;
}

export function priceIdFor(priceIds: Record<string, string> | undefined, cycle: 'monthly' | 'annual'): string | null {
  if (!priceIds) return null;
  const entries = Object.entries(priceIds).filter((entry) => typeof entry[1] === 'string' && entry[1].length > 0);
  if (cycle === 'monthly') {
    return (
      priceIds.monthly ||
      priceIds.proMonthly ||
      priceIds.month ||
      entries.find(([key]) => /month/i.test(key))?.[1] ||
      null
    );
  }
  return (
    priceIds.annual ||
    priceIds.proAnnual ||
    priceIds.year ||
    entries.find(([key]) => /annual|year/i.test(key))?.[1] ||
    null
  );
}

export function fillStatus(node: HTMLElement, message: string, upgradeUrl?: string): void {
  node.replaceChildren(document.createTextNode(message));
  if (!upgradeUrl) return;
  node.append(document.createTextNode(' '));
  const link = document.createElement('a');
  link.href = upgradeUrl;
  link.textContent = 'See pricing';
  node.append(link);
}

export function bindEmailForm(form: HTMLFormElement, status: HTMLElement, onSent: () => void): void {
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const input = form.querySelector<HTMLInputElement>('input[type="email"]');
    const email = input?.value.trim() ?? '';
    if (!input || !input.checkValidity() || email.length === 0) {
      input?.reportValidity();
      return;
    }
    const button = form.querySelector<HTMLButtonElement>('button[type="submit"]');
    if (button) button.disabled = true;
    fillStatus(status, 'Sending a sign-in link.');
    void startEmailLogin(email)
      .then(() => {
        fillStatus(status, 'Check your email for a sign-in link.');
        onSent();
      })
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : 'The sign-in email could not be sent. Try again.';
        fillStatus(status, message);
      })
      .finally(() => {
        if (button) button.disabled = false;
      });
  });
}
