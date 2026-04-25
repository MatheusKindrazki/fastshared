import type { RetentionPolicy } from '~/db/schema';

export type { RetentionPolicy } from '~/db/schema';

// Grace window between link expiry and R2 object deletion. Gives us 24h to
// reverse a bad expiry/backfill without irrecoverable data loss.
export const DELETE_GRACE_SECONDS = 86_400;

const MIN_CUSTOM_SECONDS = 300;
const MAX_CUSTOM_SECONDS = 2_592_000; // 30 days

const PRESET_SECONDS: Record<Exclude<RetentionPolicy, 'custom'>, number> = {
  oneMinute: 60,
  oneHour: 3_600,
  oneDay: 86_400,
  oneWeek: 604_800,
  oneMonth: 2_592_000,
};

export interface ResolveRetentionInput {
  policy: string;
  customTtlSeconds?: number | undefined;
}

export interface ResolvedRetention {
  expiresAt: Date;
  deleteAfter: Date;
  retentionPolicy: RetentionPolicy;
}

export function resolveRetention(
  input: ResolveRetentionInput,
  now: Date = new Date(),
): ResolvedRetention {
  const policy = asRetentionPolicy(input.policy);
  const ttlSeconds = resolveTtlSeconds(policy, input.customTtlSeconds);
  const expiresAt = new Date(now.getTime() + ttlSeconds * 1000);
  const deleteAfter = new Date(expiresAt.getTime() + DELETE_GRACE_SECONDS * 1000);
  return { expiresAt, deleteAfter, retentionPolicy: policy };
}

function asRetentionPolicy(value: string): RetentionPolicy {
  switch (value) {
    case 'oneMinute':
    case 'oneHour':
    case 'oneDay':
    case 'oneWeek':
    case 'oneMonth':
    case 'custom':
      return value;
    default:
      throw new Error(`unsupported retention policy: ${value}`);
  }
}

function resolveTtlSeconds(policy: RetentionPolicy, customSeconds: number | undefined): number {
  if (policy !== 'custom') return PRESET_SECONDS[policy];
  if (customSeconds === undefined) {
    throw new Error('customTtlSeconds is required when policy is "custom"');
  }
  if (!Number.isFinite(customSeconds) || !Number.isInteger(customSeconds)) {
    throw new Error('customTtlSeconds must be an integer');
  }
  if (customSeconds < MIN_CUSTOM_SECONDS) return MIN_CUSTOM_SECONDS;
  if (customSeconds > MAX_CUSTOM_SECONDS) return MAX_CUSTOM_SECONDS;
  return customSeconds;
}
