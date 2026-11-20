import {
  ApiError,
  apiBase,
  apiJson,
  bindEmailForm,
  clearToken,
  consumeHashToken,
  fillStatus,
  linkWithAppCode,
  readToken,
  type PublicationSummary,
} from './session';

type PortalBody = { url?: string; portalUrl?: string; href?: string };

function formatWhen(value: string | null): string {
  if (!value) return 'Does not expire';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('en', { dateStyle: 'medium', timeStyle: 'short' }).format(date);
}

function text(tag: string, value: string, className?: string): HTMLElement {
  const node = document.createElement(tag);
  if (className) node.className = className;
  node.textContent = value;
  return node;
}

function row(label: string, value: string): HTMLElement {
  const wrap = document.createElement('div');
  wrap.className = 'meta';
  wrap.append(text('dt', label), text('dd', value));
  return wrap;
}

async function portalUrl(token: string): Promise<string> {
  const res = await fetch(`${apiBase()}/v1/billing/portal`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    redirect: 'manual',
  });
  if (res.status >= 300 && res.status < 400) {
    const location = res.headers.get('Location');
    if (location) return location;
  }
  const text = await res.text();
  if (!res.ok) {
    throw new ApiError('Billing is not available yet.', res.status, 'billing_unavailable');
  }
  try {
    const body = JSON.parse(text) as PortalBody;
    const url = body.url || body.portalUrl || body.href;
    if (typeof url === 'string' && url.length > 0) return url;
  } catch {
    if (/^https?:\/\//.test(text.trim())) return text.trim();
  }
  throw new ApiError('Billing did not return a link.', 502, 'billing_unavailable');
}

function renderPublication(pub: PublicationSummary, token: string, reload: () => Promise<void>, status: HTMLElement): HTMLElement {
  const article = document.createElement('article');
  article.className = 'pub';
  const heading = pub.title && pub.title.length > 0 ? pub.title : pub.slug;
  article.append(text('h2', heading));
  if (pub.url) {
    const link = document.createElement('a');
    link.href = pub.url;
    link.textContent = pub.url;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    article.append(link);
  }
  const meta = document.createElement('dl');
  meta.append(
    row('Status', pub.status),
    row('Current version', pub.currentVersion === null ? 'None' : String(pub.currentVersion)),
    row('Expires', formatWhen(pub.expires_at)),
    row('Opens, last 7 days', String(pub.opensLast7Days ?? 0)),
  );
  article.append(meta);
  if (pub.status !== 'revoked') {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'btn-ghost';
    button.textContent = 'Revoke';
    button.setAttribute('aria-label', `Revoke ${heading}`);
    button.addEventListener('click', () => {
      const confirmed = window.confirm('Revoke this publication? The link stops serving immediately.');
      if (!confirmed) return;
      button.disabled = true;
      void apiJson(`/v1/publications/${pub.id}/revoke`, { method: 'POST', token })
        .then(() => reload())
        .catch((error: unknown) => {
          fillStatus(status, error instanceof Error ? error.message : 'The publication could not be revoked.');
          button.disabled = false;
        });
    });
    article.append(button);
  }
  return article;
}

export function mountAccount(root: HTMLElement): void {
  const signedOut = root.querySelector<HTMLElement>('[data-signed-out]');
  const signedIn = root.querySelector<HTMLElement>('[data-signed-in]');
  const signIn = root.querySelector<HTMLFormElement>('[data-sign-in]');
  const signInStatus = root.querySelector<HTMLElement>('[data-sign-in-status]');
  const list = root.querySelector<HTMLElement>('[data-list]');
  const empty = root.querySelector<HTMLElement>('[data-empty]');
  const status = root.querySelector<HTMLElement>('[data-account-status]');
  const billing = root.querySelector<HTMLButtonElement>('[data-billing]');
  const signOut = root.querySelector<HTMLButtonElement>('[data-sign-out]');
  const linkForm = root.querySelector<HTMLFormElement>('[data-link-code]');
  const linkStatus = root.querySelector<HTMLElement>('[data-link-status]');
  if (!signedOut || !signedIn || !signIn || !signInStatus || !list || !empty || !status || !billing || !signOut) return;

  const paint = () => {
    const token = readToken();
    signedOut.hidden = Boolean(token);
    signedIn.hidden = !token;
  };

  const load = async () => {
    const token = readToken();
    paint();
    if (!token) return;
    fillStatus(status, 'Loading publications.');
    try {
      const body = await apiJson<{ publications: PublicationSummary[] }>('/v1/publications', { token });
      const publications = body.publications ?? [];
      list.replaceChildren();
      empty.hidden = publications.length > 0;
      for (const pub of publications) list.append(renderPublication(pub, token, load, status));
      fillStatus(status, '');
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) {
        clearToken();
        paint();
      }
      fillStatus(status, error instanceof Error ? error.message : 'Publications could not be loaded.');
    }
  };

  linkForm?.addEventListener('submit', (event) => {
    event.preventDefault();
    const input = linkForm.querySelector<HTMLInputElement>('input[name="code"]');
    const button = linkForm.querySelector<HTMLButtonElement>('button[type="submit"]');
    const code = (input?.value ?? '').replace(/\s+/g, '');
    if (button) button.disabled = true;
    if (linkStatus) fillStatus(linkStatus, 'Linking this browser.');
    void linkWithAppCode(code)
      .then(async () => {
        if (linkStatus) fillStatus(linkStatus, '');
        await load();
      })
      .catch((error: unknown) => {
        if (linkStatus) fillStatus(linkStatus, error instanceof Error ? error.message : 'Linking failed.');
      })
      .finally(() => {
        if (button) button.disabled = false;
      });
  });

  consumeHashToken();
  bindEmailForm(signIn, signInStatus, () => undefined);
  signOut.addEventListener('click', () => {
    clearToken();
    list.replaceChildren();
    paint();
    fillStatus(status, 'Signed out on this browser.');
  });
  billing.addEventListener('click', () => {
    const token = readToken();
    if (!token) return;
    billing.disabled = true;
    void portalUrl(token)
      .then((url) => {
        window.location.assign(url);
      })
      .catch((error: unknown) => {
        fillStatus(status, error instanceof Error ? error.message : 'Billing is not available yet.');
        billing.disabled = false;
      });
  });
  void load();
}

const root = document.querySelector<HTMLElement>('[data-account-root]');
if (root) mountAccount(root);
