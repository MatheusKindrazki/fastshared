# Plan B — Pro Feature (Apple) QA Matrix

One-page manual checklist run on physical iPhone + Simulator + Mac with a
Sandbox Apple ID. Every row MUST be exercised end-to-end before shipping.

Not automated — Apple Sandbox + physical-device dependent; the SwiftPM test
suite validates the non-StoreKit logic.

## Prerequisites

- Xcode run scheme: `FastSharedApp` (attaches `apple/FastSharedApp/FastShared.storekit`).
- Sandbox Apple ID signed in under System Settings → Apple ID (Mac) or
  Settings → App Store → Sandbox Account (iPhone).
- iCloud Drive on, signed-in account matches.
- `iCloud.dev.kindrazki.fastshared` container registered in ASC for both the
  main App ID and the share extension App ID (flagged in followups —
  **blocker** otherwise).
- Plan A backend accessible (or monkey-patch `APIClient` for Plan B-only QA).

## Matrix

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 1 | Fresh install, Free | Fresh install → share 1 file, share 2, share 3 (OK); 4th → share sheet shows preflight → paywall | 3 uploads succeed, 4th opens paywall with `.dailyCapReached(3, 3)` hero |
| 2 | Buy Monthly | On #1 paywall, tap Monthly → sandbox prompt → confirm | `isPro` flips → "Pro" in Settings → 4th upload succeeds → Usage row shows `4 / ∞` |
| 3 | Buy Annual | Restart app Free → share 4 → tap Annual → confirm | Annual card showed `SAVE 44%` badge; post-purchase engine starts; toggle Sync row works |
| 4 | Annual cancel → downgrade | In TestFlight Sandbox, cancel subscription → advance sandbox clock past expiry | Engine logs "stopped; cloud records retained"; no local row deletion; UI flips back to Free |
| 5 | Buy Lifetime → reinstall | Buy Lifetime from paywall → note tier → delete app → reinstall → hit paywall → Restore | Restore reinstates Pro with `tier=lifetime`, no expiry |
| 6 | 2-device sync | Two devices both Pro, both toggle Sync on → upload on A → wait ~30s → open B | `ShareLinkEntity` row for the new token appears on B; filename + short URL match |
| 7 | Large file Free | Free tier → import 200 MB file via file-picker | Paywall opens with `.largeFileRequested(sizeBytes: …)` — staging file cleaned on cancel |
| 8 | Large file Pro | Pro tier → same 200 MB file | Upload proceeds normally |
| 9 | Long TTL Free | Free tier share ext → tap "1 week" pill | Paywall opens with `.longRetentionRequested(.oneWeek)`; selection reverts to "24h" |
| 10 | Long TTL Pro | Pro tier share ext → tap "1 week" | Selection sticks; upload proceeds with 1-week TTL |
| 11 | Cloud sync toggle Free | Free, open Settings → tap Sync row | Paywall `.cloudSyncRequested`; toggle never flips |
| 12 | Cloud sync toggle Pro | Pro, Settings → toggle off → relaunch | Toggle persists OFF; engine stopped; no new records pushed |
| 13 | Cold launch after buy | Buy monthly → force-quit → open app | No "Free flash"; Pro rendered within 1–2 s from cache + handshake |
| 14 | Server 402 passthrough | Mock backend → return 402 `pro_required` for `/v1/uploads` | HistoryView upload path surfaces paywall `.serverForced("pro_required")` |
| 15 | Free cap hit via share ext | Free, already at 3/3 via main app → invoke share extension | Share-ext paywall sheet opens (inline) with daily-cap hero; no upload attempt |
| 16 | Reduce Motion | iOS Accessibility → Reduce Motion ON → open paywall → dismiss | No spring; instant fade |
| 17 | Dynamic Type | Accessibility Inspector → `.accessibility1` → open paywall | No truncation on iPhone 15; tier cards stack |
| 18 | VoiceOver | Enable VoiceOver → rotor through paywall | "Close paywall" button labelled; each tier card announces plan + price + features + "Double tap to subscribe" |
| 19 | macOS paywall | Mac → Hit Pro gate | Sheet opens 520×720; dismisses via Esc or drag indicator |
| 20 | App Group isolation | Share ext triggers paywall → main app already open | Share ext's inline `SharePaywallSheet` opens; main app paywall stays dismissed |

## Sign-off

- [ ] All 20 rows PASS on `iPhone 15 Pro` (iOS 17.4+)
- [ ] All 20 rows PASS on `iPad Pro` (iOS 17.4+)
- [ ] All 20 rows PASS on `Mac` (macOS 14+)
- [ ] Console logs free of `error` / `fault` during flow
- [ ] No staging file leak in `group.dev.kindrazki.fastshared/staging` after cancel
