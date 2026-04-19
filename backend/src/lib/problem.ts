import type { Context } from 'hono';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import type { AppBindings } from '~/env';

export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  detail?: string;
  code: string;
  requestId: string;
}

const BASE_TYPE = 'https://fastsha.red/problems';

export function problem(
  c: Context<AppBindings>,
  status: ContentfulStatusCode,
  code: string,
  title: string,
  detail?: string,
  extras?: Record<string, unknown>,
): Response {
  const body: ProblemDetails & Record<string, unknown> = {
    type: `${BASE_TYPE}/${code}`,
    title,
    status,
    code,
    requestId: c.get('requestId') ?? 'unknown',
    ...(detail ? { detail } : {}),
    ...(extras ?? {}),
  };
  return c.json(body, status, { 'content-type': 'application/problem+json' });
}
