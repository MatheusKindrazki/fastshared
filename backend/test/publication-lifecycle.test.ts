import { describe, expect, it } from 'vitest';
import { nextPublicationState } from '~/services/publicationLifecycle';

const now = new Date('2026-11-15T12:00:00Z');
const base = {
  status: 'active',
  ownerUserId: null,
  createdAt: new Date(now.getTime() - 8 * 86400_000),
  expiresAt: new Date(now.getTime() - 86400_000),
  updatedAt: now,
};

describe('publication lifecycle', () => {
  it('expires Free at day 7 and deletes 24 hours later', () => {
    expect(nextPublicationState(base, false, now)).toEqual({ status: 'expired' });
    expect(nextPublicationState({ ...base, status: 'expired' }, false, now)).toEqual({
      deletePrefix: true,
    });
  });
  it('keeps active Pro without expiry and starts 30 days when canceled', () => {
    const pro = { ...base, ownerUserId: 'user', expiresAt: null };
    expect(nextPublicationState(pro, true, now)).toEqual({});
    expect(nextPublicationState(pro, false, now)).toEqual({
      expiresAt: new Date(now.getTime() + 30 * 86400_000),
    });
    expect(
      nextPublicationState(
        { ...pro, expiresAt: new Date(now.getTime() + 10 * 86400_000) },
        true,
        now,
      ),
    ).toEqual({ expiresAt: null });
    expect(
      nextPublicationState(
        { ...pro, status: 'expired', expiresAt: new Date(now.getTime() - 1000) },
        true,
        now,
      ),
    ).toEqual({ status: 'active', expiresAt: null });
  });
  it('deletes revoked publications immediately', () => {
    expect(nextPublicationState({ ...base, status: 'revoked' }, false, now)).toEqual({
      deletePrefix: true,
    });
  });
});
