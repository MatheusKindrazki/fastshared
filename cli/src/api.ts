import { createReadStream } from 'node:fs';
import { Readable } from 'node:stream';
import type { RetentionPolicy } from './options.js';

export interface DeviceRegistration {
  deviceId: string;
  deviceToken: string;
}

export interface UploadInput {
  filePath: string;
  filename: string;
  contentType: string;
  sizeBytes: number;
  sha256: string;
  retentionPolicy: RetentionPolicy;
}

export interface UploadResult {
  shortUrl: string;
  token: string;
  expiresAt: string;
  deleteAfter: string;
  linkStatus: string;
  retentionPolicy: string;
  assetId?: string;
}

interface UploadInstructionSingle {
  mode: 'single';
  url: string;
  method: 'PUT';
  headers: Record<string, string>;
  expiresAt: string;
}

interface UploadInstructionMultipart {
  mode: 'multipart';
  multipartUploadId: string;
  partSize: number;
  parts: Array<{ partNumber: number; url: string; method: 'PUT' }>;
  expiresAt: string;
}

type UploadInstruction = UploadInstructionSingle | UploadInstructionMultipart;

interface PresignResponse {
  uploadId?: string;
  upload?: UploadInstruction;
  shortUrl?: string;
  token?: string;
  expiresAt?: string;
  deleteAfter?: string;
  linkStatus?: string;
  retentionPolicy?: string;
  deduped?: {
    assetId: string;
    shortUrl: string;
    token: string;
    expiresAt: string;
    deleteAfter: string;
    retentionPolicy: string;
  };
}

interface CompleteResponse {
  assetId: string;
  shortUrl: string;
  token: string;
  expiresAt: string;
  deleteAfter: string;
  linkStatus: string;
  retentionPolicy: string;
}

interface ProblemBody {
  status?: number;
  code?: string;
  title?: string;
  detail?: string;
}

export class FastSharedHttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
    readonly detail?: string,
  ) {
    super(message);
  }
}

export class FastSharedApi {
  private readonly apiBaseUrl: string;
  private readonly fetchImpl: typeof fetch;

  constructor(options: { apiBaseUrl: string; fetchImpl?: typeof fetch }) {
    this.apiBaseUrl = options.apiBaseUrl.replace(/\/+$/, '');
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async registerDevice(appVersion: string): Promise<DeviceRegistration> {
    return this.requestJson<DeviceRegistration>('/v1/devices', {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ platform: 'cli', appVersion }),
    });
  }

  async uploadFile(input: UploadInput, deviceToken: string): Promise<UploadResult> {
    const presign = await this.requestJson<PresignResponse>(
      '/v1/uploads',
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json',
          authorization: `Bearer ${deviceToken}`,
        },
        body: JSON.stringify({
          clientJobId: crypto.randomUUID(),
          contentType: input.contentType,
          sizeBytes: input.sizeBytes,
          sha256: input.sha256,
          originalFilename: input.filename,
          retentionPolicy: input.retentionPolicy,
        }),
      },
    );

    if (presign.deduped) {
      return {
        assetId: presign.deduped.assetId,
        shortUrl: presign.deduped.shortUrl,
        token: presign.deduped.token,
        expiresAt: presign.deduped.expiresAt,
        deleteAfter: presign.deduped.deleteAfter,
        linkStatus: 'active',
        retentionPolicy: presign.deduped.retentionPolicy,
      };
    }

    if (!presign.uploadId || !presign.upload) {
      throw new Error('invalid presign response: missing uploadId/upload');
    }

    let usedMultipart = false;
    try {
      let multipart: { parts: Array<{ partNumber: number; eTag: string }> } | undefined;
      if (presign.upload.mode === 'multipart') {
        usedMultipart = true;
        multipart = { parts: await this.putMultipart(input.filePath, input.sizeBytes, presign.upload) };
      } else {
        await this.putSingle(input.filePath, presign.upload);
      }

      const complete = await this.requestJson<CompleteResponse>(
        `/v1/uploads/${encodeURIComponent(presign.uploadId)}/complete`,
        {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            accept: 'application/json',
            authorization: `Bearer ${deviceToken}`,
          },
          body: JSON.stringify({
            contentType: input.contentType,
            sizeBytes: input.sizeBytes,
            sha256: input.sha256,
            originalFilename: input.filename,
            ...(multipart ? { multipart } : {}),
          }),
        },
      );
      return complete;
    } catch (err) {
      if (usedMultipart) await this.abortMultipart(presign.uploadId, deviceToken).catch(() => undefined);
      else await this.markFailed(presign.uploadId, deviceToken, err).catch(() => undefined);
      throw err;
    }
  }

  private async putSingle(filePath: string, upload: UploadInstructionSingle): Promise<void> {
    const response = await this.fetchImpl(upload.url, {
      method: upload.method,
      headers: upload.headers,
      body: Readable.toWeb(createReadStream(filePath)) as BodyInit,
      duplex: 'half',
    } as RequestInit & { duplex: 'half' });
    if (!response.ok) {
      throw new FastSharedHttpError(response.status, `R2 upload failed with HTTP ${response.status}`);
    }
  }

  private async putMultipart(
    filePath: string,
    sizeBytes: number,
    upload: UploadInstructionMultipart,
  ): Promise<Array<{ partNumber: number; eTag: string }>> {
    const parts: Array<{ partNumber: number; eTag: string }> = [];
    for (const part of upload.parts.slice().sort((a, b) => a.partNumber - b.partNumber)) {
      const start = (part.partNumber - 1) * upload.partSize;
      const end = Math.min(start + upload.partSize, sizeBytes) - 1;
      const length = end - start + 1;
      const response = await this.fetchImpl(part.url, {
        method: part.method,
        headers: { 'content-length': String(length) },
        body: Readable.toWeb(createReadStream(filePath, { start, end })) as BodyInit,
        duplex: 'half',
      } as RequestInit & { duplex: 'half' });
      if (!response.ok) {
        throw new FastSharedHttpError(
          response.status,
          `R2 multipart part ${part.partNumber} failed with HTTP ${response.status}`,
        );
      }
      const eTag = response.headers.get('etag');
      if (!eTag) throw new Error(`R2 multipart part ${part.partNumber} did not return an ETag`);
      parts.push({ partNumber: part.partNumber, eTag });
    }
    return parts;
  }

  private async markFailed(uploadId: string, deviceToken: string, err: unknown): Promise<void> {
    await this.requestVoid(`/v1/uploads/${encodeURIComponent(uploadId)}/fail`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${deviceToken}`,
      },
      body: JSON.stringify({
        errorCode: 'cli_upload_failed',
        detail: err instanceof Error ? err.message : String(err),
      }),
    });
  }

  private async abortMultipart(uploadId: string, deviceToken: string): Promise<void> {
    await this.requestVoid(`/v1/uploads/${encodeURIComponent(uploadId)}/abort-multipart`, {
      method: 'POST',
      headers: { authorization: `Bearer ${deviceToken}` },
    });
  }

  private async requestJson<T>(path: string, init: RequestInit): Promise<T> {
    const response = await this.fetchImpl(`${this.apiBaseUrl}${path}`, init);
    if (!response.ok) throw await this.toHttpError(response);
    return (await response.json()) as T;
  }

  private async requestVoid(path: string, init: RequestInit): Promise<void> {
    const response = await this.fetchImpl(`${this.apiBaseUrl}${path}`, init);
    if (!response.ok) throw await this.toHttpError(response);
  }

  private async toHttpError(response: Response): Promise<FastSharedHttpError> {
    const problem = (await response
      .clone()
      .json()
      .catch(() => null)) as ProblemBody | null;
    const title = problem?.title ?? (response.statusText || 'HTTP error');
    const detail = problem?.detail;
    const code = problem?.code;
    return new FastSharedHttpError(
      response.status,
      detail ? `${title}: ${detail}` : `${title} (${response.status})`,
      code,
      detail,
    );
  }
}
