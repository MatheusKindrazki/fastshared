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

// ⚠️ TEMPORARY OVERRIDE — 2026-04-20
// Apple Paid Apps Agreement is still pending user information (W-8BEN + BR
// tax form + bank account), so StoreKit returns 0 products in sandbox and
// TestFlight users can't unlock Pro via purchase. To unblock beta testing,
// FREE_CAPS is temporarily mirrored onto PRO_CAPS so every gate passes.
// REVERT this back to the canonical free tier (3 uploads/day, 100 MB, 24h)
// as soon as the Paid Apps Agreement flips to "Active" and StoreKit returns
// the three IAPs (`red.fastsha.pro.*`).
//
// Canonical Free values to restore:
//   uploadsPerDay: 3, maxFileSizeMB: 100, maxRetentionHours: 24
export const FREE_CAPS: TierCaps = {
  uploadsPerDay: -1,
  maxFileSizeMB: 2048,
  maxRetentionHours: 720,
  allowsCloudSync: true,
};

export const PRO_CAPS: TierCaps = {
  uploadsPerDay: -1,
  maxFileSizeMB: 2048,
  maxRetentionHours: 720,
  allowsCloudSync: true,
};
