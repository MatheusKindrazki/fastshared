import { zipSync } from 'fflate';
import { ApiError, apiJson, bindEmailForm, clearToken, consumeHashToken, fillStatus, readToken } from './session';

type Kind = 'site' | 'pdf';

type Staged = {
  kind: Kind;
  filename: string;
  contentType: string;
  bytes: Uint8Array;
  label: string;
};

type CreateResponse = {
  id: string;
  slug: string;
  url: string | null;
  version: number;
  upload: { url: string; method: string; headers: Record<string, string> };
};

type CompleteResponse = {
  url?: string;
  version?: number;
};

const MAX_BYTES = 250 * 1024 * 1024;

interface FileSystemEntryLike {
  isFile: boolean;
  isDirectory: boolean;
  name: string;
}

interface FileSystemFileEntryLike extends FileSystemEntryLike {
  file: (success: (file: File) => void, failure?: (error: DOMException) => void) => void;
}

interface FileSystemDirectoryEntryLike extends FileSystemEntryLike {
  createReader: () => {
    readEntries: (
      success: (entries: FileSystemEntryLike[]) => void,
      failure?: (error: DOMException) => void,
    ) => void;
  };
}

function entryOf(item: DataTransferItem): FileSystemEntryLike | null {
  const withEntry = item as DataTransferItem & {
    webkitGetAsEntry?: () => FileSystemEntryLike | null;
  };
  return withEntry.webkitGetAsEntry?.() ?? null;
}

function fileOf(entry: FileSystemFileEntryLike): Promise<File> {
  return new Promise((resolve, reject) => {
    entry.file(resolve, reject);
  });
}

function readEntries(entry: FileSystemDirectoryEntryLike): Promise<FileSystemEntryLike[]> {
  const reader = entry.createReader();
  return new Promise((resolve, reject) => {
    const all: FileSystemEntryLike[] = [];
    const next = () => {
      reader.readEntries((batch) => {
        if (batch.length === 0) {
          resolve(all);
          return;
        }
        all.push(...batch);
        next();
      }, reject);
    };
    next();
  });
}

function assertSafePath(path: string): void {
  if (path.startsWith('/') || path.includes('\\') || path.split('/').includes('..')) {
    throw new Error('This folder contains a path we cannot publish. Use relative paths only.');
  }
}

async function collect(
  entry: FileSystemEntryLike,
  path: string,
  files: Record<string, Uint8Array>,
): Promise<void> {
  assertSafePath(path);
  if (entry.isFile) {
    const file = await fileOf(entry as FileSystemFileEntryLike);
    files[path] = new Uint8Array(await file.arrayBuffer());
    return;
  }
  const children = await readEntries(entry as FileSystemDirectoryEntryLike);
  for (const child of children) {
    await collect(child, `${path}/${child.name}`, files);
  }
}

function safeStem(name: string): string {
  const stem = name.replace(/[\\/]/g, '').replace(/\.[^.]+$/, '').slice(0, 80);
  return stem.length > 0 ? stem : 'site';
}

function zipFiles(files: Record<string, Uint8Array>, filename: string, label: string): Staged {
  const paths = Object.keys(files);
  if (paths.length === 0) throw new Error('That folder is empty.');
  for (const path of paths) assertSafePath(path);
  const bytes = zipSync(files, { level: 6 });
  return {
    kind: 'site',
    filename,
    contentType: 'application/zip',
    bytes,
    label,
  };
}

async function stagedFromFile(file: File): Promise<Staged> {
  const name = file.name || 'upload';
  const lower = name.toLowerCase();
  if (lower.endsWith('.zip') || file.type === 'application/zip') {
    return {
      kind: 'site',
      filename: name.slice(0, 255),
      contentType: 'application/zip',
      bytes: new Uint8Array(await file.arrayBuffer()),
      label: name,
    };
  }
  if (lower.endsWith('.pdf') || file.type === 'application/pdf') {
    return {
      kind: 'pdf',
      filename: name.slice(0, 255),
      contentType: 'application/pdf',
      bytes: new Uint8Array(await file.arrayBuffer()),
      label: name,
    };
  }
  if (lower.endsWith('.html') || lower.endsWith('.htm') || file.type === 'text/html') {
    const inner = lower.endsWith('.htm') || lower.endsWith('.html') ? name : 'index.html';
    return zipFiles({ [inner]: new Uint8Array(await file.arrayBuffer()) }, `${safeStem(name)}.zip`, name);
  }
  throw new Error('Drop a folder, a ZIP, an HTML file, or a PDF.');
}

async function stagedFromList(files: FileList): Promise<Staged> {
  const list = [...files];
  if (list.length === 0) throw new Error('Choose a folder, a ZIP, an HTML file, or a PDF.');
  const relative = list[0]?.webkitRelativePath ?? '';
  if (relative.includes('/')) {
    const packed: Record<string, Uint8Array> = {};
    const root = relative.split('/')[0] || 'site';
    for (const file of list) {
      const parts = (file.webkitRelativePath || file.name).split('/');
      const path = (parts.length > 1 ? parts.slice(1) : parts).join('/');
      if (!path) continue;
      assertSafePath(path);
      packed[path] = new Uint8Array(await file.arrayBuffer());
    }
    return zipFiles(packed, `${safeStem(root)}.zip`, root);
  }
  if (list.length !== 1 || !list[0]) throw new Error('Drop one folder, one ZIP, one HTML file, or one PDF.');
  return stagedFromFile(list[0]);
}

async function stagedFromTransfer(transfer: DataTransfer): Promise<Staged> {
  const items = [...transfer.items].filter((item) => item.kind === 'file');
  if (items.length === 1 && items[0]) {
    const entry = entryOf(items[0]);
    if (entry?.isDirectory) {
      const packed: Record<string, Uint8Array> = {};
      const children = await readEntries(entry as FileSystemDirectoryEntryLike);
      for (const child of children) await collect(child, child.name, packed);
      return zipFiles(packed, `${safeStem(entry.name)}.zip`, entry.name);
    }
    const file = items[0].getAsFile();
    if (file) return stagedFromFile(file);
  }
  if (transfer.files.length === 1 && transfer.files[0]) return stagedFromFile(transfer.files[0]);
  throw new Error('Drop one folder, one ZIP, one HTML file, or one PDF.');
}

function guardSize(staged: Staged): void {
  if (staged.bytes.byteLength <= 0) throw new Error('That file is empty.');
  if (staged.bytes.byteLength > MAX_BYTES) throw new Error('This file is over the 250 MB publication limit.');
}

async function publish(token: string, staged: Staged, title: string, setStatus: (message: string) => void): Promise<string> {
  guardSize(staged);
  setStatus('Creating the publication.');
  const created = await apiJson<CreateResponse>('/v1/publications', {
    method: 'POST',
    token,
    body: {
      ...(title ? { title } : {}),
      kind: staged.kind,
      filename: staged.filename,
      sizeBytes: staged.bytes.byteLength,
      contentType: staged.contentType,
    },
  });
  setStatus('Uploading.');
  const upload = await fetch(created.upload.url, {
    method: created.upload.method || 'PUT',
    headers: created.upload.headers,
    body: new Blob([staged.bytes.slice()]),
  });
  if (!upload.ok) throw new Error('The upload did not finish. Try again.');
  setStatus('Finishing.');
  const completed = await apiJson<CompleteResponse>(
    `/v1/publications/${created.id}/versions/${created.version}/complete`,
    { method: 'POST', token },
  );
  return completed.url || created.url || '';
}

function show(status: HTMLElement, error: unknown): void {
  if (error instanceof ApiError) {
    fillStatus(status, error.message, error.upgradeUrl);
    if (error.status === 401) {
      /* caller clears the session */
    }
    return;
  }
  fillStatus(status, error instanceof Error ? error.message : 'The publication could not be created. Try again.');
}

export function mountPublish(root: HTMLElement): void {
  const signedOut = root.querySelector<HTMLElement>('[data-signed-out]');
  const signedIn = root.querySelector<HTMLElement>('[data-signed-in]');
  const signIn = root.querySelector<HTMLFormElement>('[data-sign-in]');
  const signInStatus = root.querySelector<HTMLElement>('[data-sign-in-status]');
  const form = root.querySelector<HTMLFormElement>('[data-publish-form]');
  const title = root.querySelector<HTMLInputElement>('#publish-title');
  const fileInput = root.querySelector<HTMLInputElement>('#publish-file');
  const folderInput = root.querySelector<HTMLInputElement>('#publish-folder');
  const drop = root.querySelector<HTMLElement>('[data-drop]');
  const chosen = root.querySelector<HTMLElement>('[data-chosen]');
  const status = root.querySelector<HTMLElement>('[data-publish-status]');
  const result = root.querySelector<HTMLElement>('[data-result]');
  const urlNode = root.querySelector<HTMLAnchorElement>('[data-url]');
  const copy = root.querySelector<HTMLButtonElement>('[data-copy]');
  if (!signedOut || !signedIn || !signIn || !signInStatus || !form || !fileInput || !folderInput || !drop || !chosen || !status || !result || !urlNode || !copy) {
    return;
  }

  let staged: Staged | null = null;
  let publishedUrl = '';

  const paintSession = () => {
    const token = readToken();
    signedOut.hidden = Boolean(token);
    signedIn.hidden = !token;
  };

  consumeHashToken();
  paintSession();
  bindEmailForm(signIn, signInStatus, () => {
    fillStatus(signInStatus, 'Check your email for a sign-in link. It opens your account.');
  });

  const remember = (next: Staged) => {
    staged = next;
    chosen.textContent = next.label;
    result.hidden = true;
  };

  folderInput.setAttribute('webkitdirectory', '');
  folderInput.setAttribute('directory', '');
  fileInput.addEventListener('change', () => {
    const files = fileInput.files;
    if (!files || files.length === 0) return;
    void stagedFromList(files).then(remember).catch((error: unknown) => show(status, error));
  });
  folderInput.addEventListener('change', () => {
    const files = folderInput.files;
    if (!files || files.length === 0) return;
    fillStatus(status, 'Packing the folder.');
    void stagedFromList(files)
      .then((next) => {
        remember(next);
        fillStatus(status, '');
      })
      .catch((error: unknown) => show(status, error));
  });

  drop.addEventListener('dragover', (event) => {
    event.preventDefault();
    drop.dataset.active = 'true';
  });
  drop.addEventListener('dragleave', () => {
    delete drop.dataset.active;
  });
  drop.addEventListener('drop', (event) => {
    event.preventDefault();
    delete drop.dataset.active;
    const transfer = event.dataTransfer;
    if (!transfer) return;
    fillStatus(status, 'Reading the drop.');
    void stagedFromTransfer(transfer)
      .then((next) => {
        remember(next);
        fillStatus(status, '');
      })
      .catch((error: unknown) => show(status, error));
  });

  copy.addEventListener('click', () => {
    if (!publishedUrl) return;
    void navigator.clipboard.writeText(publishedUrl).then(() => {
      copy.textContent = 'Copied';
    }).catch(() => {
      urlNode.focus();
    });
  });

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const token = readToken();
    if (!token || !staged) {
      fillStatus(status, staged ? 'Sign in before publishing.' : 'Choose a folder, a ZIP, an HTML file, or a PDF.');
      return;
    }
    const button = form.querySelector<HTMLButtonElement>('button[type="submit"]');
    if (button) button.disabled = true;
    const titleValue = title?.value.trim().slice(0, 200) ?? '';
    void publish(token, staged, titleValue, (message) => fillStatus(status, message))
      .then((url) => {
        publishedUrl = url;
        urlNode.href = url;
        urlNode.textContent = url;
        result.hidden = false;
        fillStatus(status, 'The link is ready.');
        copy.textContent = 'Copy link';
        urlNode.focus();
      })
      .catch((error: unknown) => {
        if (error instanceof ApiError && error.status === 401) {
          clearToken();
          paintSession();
        }
        show(status, error);
      })
      .finally(() => {
        if (button) button.disabled = false;
      });
  });
}

const root = document.querySelector<HTMLElement>('[data-publish-root]');
if (root) mountPublish(root);
