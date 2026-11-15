// Single source of truth for per-tier quota limits. Both the free-tier
// enforcement middleware and `GET /v1/me` read these — no drift allowed.
//
// Values are aligned with the v1.1 Pro tier launch plan:
//   Free:  3 uploads/day, max 100 MB, TTL up to 24h, no Cloud Sync
//   Pro:   unlimited (-1 sentinel) uploads, max 2 GB, TTL up to 30 days, Cloud Sync

export interface TierCaps {
  uploadsPerDay: number; // -1 means unlimited
  maxFileSizeMB: number;
  maxRetentionHours: number;
  allowsCloudSync: boolean;
}

/// Wire-shape the iOS client expects for `GET /v1/me` `.caps`. Names/units
/// diverge from the internal `TierCaps` on purpose (client thinks in bytes and
/// seconds), so routes serialize via `toWireCaps()` before responding.
export interface TierCapsWire {
  dailyUploadLimit: number | null;
  maxFileSizeBytes: number;
  maxRetentionSeconds: number;
  allowsCloudSync: boolean;
}

export function toWireCaps(caps: TierCaps): TierCapsWire {
  return {
    dailyUploadLimit: caps.uploadsPerDay < 0 ? null : caps.uploadsPerDay,
    maxFileSizeBytes: caps.maxFileSizeMB * 1024 * 1024,
    maxRetentionSeconds: caps.maxRetentionHours * 3600,
    allowsCloudSync: caps.allowsCloudSync,
  };
}

export const FREE_CAPS: TierCaps = {
  uploadsPerDay: 3,
  maxFileSizeMB: 100,
  maxRetentionHours: 24,
  allowsCloudSync: false,
};

export const PRO_CAPS: TierCaps = {
  uploadsPerDay: -1,
  maxFileSizeMB: 2048,
  maxRetentionHours: 720,
  allowsCloudSync: true,
};

export const PUBLICATION_FREE_CAPS = {
  activePublications: 1,
  maxUploadBytes: 25 * 1024 * 1024,
  maxStorageBytes: 25 * 1024 * 1024,
  lifetimeDays: 7,
  openAlerts: 3,
} as const;

export const PUBLICATION_PRO_CAPS = {
  activePublications: Number.POSITIVE_INFINITY,
  maxUploadBytes: 250 * 1024 * 1024,
  maxStorageBytes: 2 * 1024 * 1024 * 1024,
  lifetimeDays: null,
  openAlerts: Number.POSITIVE_INFINITY,
} as const;
