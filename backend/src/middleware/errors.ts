import type { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { ZodError } from 'zod';
import type { AppBindings } from '~/env';
import { log } from '~/lib/logger';
import { problem } from '~/lib/problem';

export const errors = (app: Hono<AppBindings>): Hono<AppBindings> => {
  app.onError((err, c) => {
    const requestId = c.get('requestId') ?? 'unknown';

    if (err instanceof ZodError) {
      log.warn({
        msg: 'validation_error',
        requestId,
        issues: err.issues,
        path: new URL(c.req.url).pathname,
      });
      return problem(
        c,
        400,
        'validation_error',
        'Invalid request',
        err.issues.map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`).join('; '),
      );
    }

    if (err instanceof HTTPException) {
      const status = err.status;
      const code = mapStatusToCode(status);
      log.warn({
        msg: 'http_exception',
        requestId,
        status,
        detail: err.message,
        path: new URL(c.req.url).pathname,
      });
      return problem(c, status, code, httpTitle(status), err.message || undefined);
    }

    log.error({
      msg: 'unhandled_error',
      requestId,
      path: new URL(c.req.url).pathname,
      error:
        err instanceof Error
          ? { name: err.name, message: err.message, stack: err.stack }
          : String(err),
    });
    return problem(c, 500, 'internal_error', 'Internal Server Error');
  });
  return app;
};

function httpTitle(status: number): string {
  switch (status) {
    case 400:
      return 'Bad Request';
    case 401:
      return 'Unauthorized';
    case 403:
      return 'Forbidden';
    case 404:
      return 'Not Found';
    case 409:
      return 'Conflict';
    case 410:
      return 'Gone';
    case 413:
      return 'Payload Too Large';
    case 415:
      return 'Unsupported Media Type';
    case 422:
      return 'Unprocessable Entity';
    case 429:
      return 'Too Many Requests';
    case 501:
      return 'Not Implemented';
    default:
      return status >= 500 ? 'Internal Server Error' : 'Request Error';
  }
}

function mapStatusToCode(status: number): string {
  switch (status) {
    case 400:
      return 'bad_request';
    case 401:
      return 'unauthorized';
    case 403:
      return 'forbidden';
    case 404:
      return 'not_found';
    case 409:
      return 'conflict';
    case 410:
      return 'gone';
    case 413:
      return 'payload_too_large';
    case 415:
      return 'unsupported_media_type';
    case 422:
      return 'unprocessable_entity';
    case 429:
      return 'rate_limited';
    case 501:
      return 'not_implemented';
    default:
      return status >= 500 ? 'internal_error' : 'request_error';
  }
}
