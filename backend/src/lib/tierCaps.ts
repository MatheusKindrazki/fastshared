// Single source of truth for per-tier quota limits. Both the free-tier
// enforcement middleware and `GET /v1/me` read these — no drift allowed.
//
// Values are aligned with memory/pricing-and-monetization.md:
//   Free:  3 uploads/day, max 100 MB, TTL fixed at 24h
//   Pro:   unlimited (-1 sentinel) uploads, max 2 GB, TTL up to 30 days

export interface TierCaps {
  uploadsPerDay: number; // -1 means unlimited
  maxFileSizeMB: number;
  maxRetentionHours: number;
}

export const FREE_CAPS: TierCaps = {
  uploadsPerDay: 3,
  maxFileSizeMB: 100,
  maxRetentionHours: 24,
};

export const PRO_CAPS: TierCaps = {
  uploadsPerDay: -1,
  maxFileSizeMB: 2048,
  maxRetentionHours: 720,
};
