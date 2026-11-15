import { describe, it, expect, afterEach, vi } from 'vitest';
import { TEST_ENV, ctx } from './support';
import worker, { isUnclaimedSubdomain } from '~/index';

const env = {
  ...TEST_ENV,
  SHORT_LINK_HOST: 'https://fastsha.red',
  PUBLIC_API_HOST: 'https://api.fastsha.red',
  USER_CONTENT_HOST: 'https://u.fastsha.red',
  PUBLICATION_HOST_SUFFIX: 'fastsha.red',
};

describe('wildcard route host ownership', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('claims only the API and user-content subdomains', () => {
    expect(isUnclaimedSubdomain('fastsha.red', env)).toBe(false);
    expect(isUnclaimedSubdomain('api.fastsha.red', env)).toBe(false);
    expect(isUnclaimedSubdomain('u.fastsha.red', env)).toBe(false);
    expect(isUnclaimedSubdomain('www.fastsha.red', env)).toBe(true);
    expect(isUnclaimedSubdomain('status.fastsha.red', env)).toBe(true);
    expect(isUnclaimedSubdomain('example.com', env)).toBe(false);
    expect(isUnclaimedSubdomain('evilfastsha.red', env)).toBe(false);
  });

  it('passes unclaimed subdomains through to their origin instead of the API', async () => {
    const origin = vi.fn(async () => new Response('origin', { status: 200 }));
    vi.stubGlobal('fetch', origin);
    const res = await worker.fetch(new Request('https://www.fastsha.red/v1/me'), env, ctx);
    expect(origin).toHaveBeenCalledTimes(1);
    expect(await res.text()).toBe('origin');
  });

  it('still serves the API on its own host', async () => {
    const origin = vi.fn(async () => new Response('origin'));
    vi.stubGlobal('fetch', origin);
    const res = await worker.fetch(new Request('https://api.fastsha.red/v1/me'), env, ctx);
    expect(origin).not.toHaveBeenCalled();
    expect(res.status).toBe(401);
  });
});
