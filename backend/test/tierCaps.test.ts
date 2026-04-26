import { describe, expect, it } from 'vitest';
import { FREE_CAPS, PRO_CAPS, toWireCaps } from '~/lib/tierCaps';

describe('launch tier caps', () => {
  it('keeps Free upload usage unlimited for launch without enabling Cloud Sync', () => {
    expect(FREE_CAPS.uploadsPerDay).toBe(-1);
    expect(FREE_CAPS.maxFileSizeMB).toBe(PRO_CAPS.maxFileSizeMB);
    expect(FREE_CAPS.maxRetentionHours).toBe(PRO_CAPS.maxRetentionHours);
    expect(FREE_CAPS.allowsCloudSync).toBe(false);

    expect(toWireCaps(FREE_CAPS)).toEqual({
      dailyUploadLimit: null,
      maxFileSizeBytes: 2 * 1024 * 1024 * 1024,
      maxRetentionSeconds: 30 * 24 * 60 * 60,
      allowsCloudSync: false,
    });
  });
});
