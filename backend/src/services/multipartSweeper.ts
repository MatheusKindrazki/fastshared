import type { Env } from '~/env';
import { abortMultipartUpload, listAbortedMultipartUploads } from '~/services/r2';
import { log } from '~/lib/logger';

const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;

export async function runMultipartSweeper(env: Env): Promise<void> {
  const stale = await listAbortedMultipartUploads({ env, olderThanMs: TWENTY_FOUR_HOURS_MS });
  log.info({ msg: 'multipart_sweeper_start', candidates: stale.length });

  let aborted = 0;
  let failed = 0;
  for (const u of stale) {
    try {
      await abortMultipartUpload({ env, key: u.key, uploadId: u.uploadId });
      aborted++;
      log.info({ msg: 'multipart_aborted', key: u.key, uploadId: u.uploadId });
    } catch (err) {
      failed++;
      log.warn({
        msg: 'multipart_abort_failed',
        key: u.key,
        uploadId: u.uploadId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  log.info({ msg: 'multipart_sweeper_done', aborted, failed });
}
