import { describe, expect, it } from 'vitest';
import { FREE_CAPS, PRO_CAPS, toWireCaps } from '~/lib/tierCaps';

describe('tier caps', () => {
  it('differentiates Free (3/day, 100 MB, 24h) from Pro (unlimited, 2 GB, 30d, Cloud Sync)', () => {
    expect(FREE_CAPS).toEqual({
      uploadsPerDay: 3,
      maxFileSizeMB: 100,
      maxRetentionHours: 24,
      allowsCloudSync: false,
    });
    expect(PRO_CAPS).toEqual({
      uploadsPerDay: -1,
      maxFileSizeMB: 2048,
      maxRetentionHours: 720,
      allowsCloudSync: true,
    });

    expect(toWireCaps(FREE_CAPS)).toEqual({
      dailyUploadLimit: 3,
      maxFileSizeBytes: 100 * 1024 * 1024,
      maxRetentionSeconds: 24 * 60 * 60,
      allowsCloudSync: false,
    });
    expect(toWireCaps(PRO_CAPS)).toEqual({
      dailyUploadLimit: null,
      maxFileSizeBytes: 2 * 1024 * 1024 * 1024,
      maxRetentionSeconds: 30 * 24 * 60 * 60,
      allowsCloudSync: true,
    });
  });
});
