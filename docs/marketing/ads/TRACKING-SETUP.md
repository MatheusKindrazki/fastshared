# FastShared — Tracking Setup

Goal: know which ad → install → first share, **without paying for an MMP**.

---

## Decision: Singular Free Tier

**Why Singular Free over alternatives:**

| Option | Cost | Cross-platform attribution | iOS SKAN handling | Verdict |
|---|---|---|---|---|
| Apple Ads Attribution API only | Free | ❌ ASA only | Native | Too narrow |
| Meta SKAN 4.0 only | Free | ❌ Meta only | Native | Too narrow |
| **Singular Free** | **Free up to 50k attributions/mo** | ✅ All channels | ✅ Manages SKAN postbacks | **Use this** |
| AppsFlyer / Adjust paid | US$ 200+/mo | ✅ | ✅ | Overkill for R$ 300/mo spend |

50k attributions = ~50k installs/mo. We'll be at 30–100/mo. Massive headroom.

---

## What needs to be installed

### 1. Singular SDK in the iOS app

Repo: `apple/` directory of this monorepo.

- Add Singular iOS SDK via SwiftPM:
  `https://github.com/singular-labs/Singular-iOS-SDK`
- Config: SDK key + secret from Singular dashboard (after free signup)
- Initialize in `AppDelegate` / SwiftUI App entry, before any networking

**Required calls:**

```swift
// On app launch
Singular.start(SingularConfig(apiKey: KEY, andSecret: SECRET))

// On the activation event
Singular.event("first_share", withArgs: [
    "share_id": shareLinkId,
    "file_count": bundleAssetCount  // 1 for single, N for bundle
])
```

The `first_share` event is the **single most important signal** in this
plan. Without it, every campaign optimizes for blind installs and Phase 1
exit gate becomes unmeasurable.

### 2. SKAN 4.0 conversion model

Singular auto-manages the SKAdNetwork conversion-value mapping. Configure
in their dashboard:

| Conversion value | Event |
|---|---|
| 0 | Install only |
| 1–10 | First share within 1h (high-intent activation) |
| 11–25 | First share within 24h |
| 26–63 | Repeat sharer within 24h |

This compresses iOS's 6-bit SKAN signal into actionable cohorts. Singular
handles the math — you just declare the events.

### 3. Apple Search Ads Attribution API (free, via Singular)

Singular dashboard → Integrations → Apple Search Ads → connect with Apple
ID that owns the App Store Connect listing. Pulls keyword-level attribution
into the same dashboard as Meta. No code change needed.

### 4. Meta App Events API (CAPI for apps, via Singular)

Singular dashboard → Integrations → Facebook → install signing certificate.
Singular auto-relays install + `first_share` events to Meta as the
optimization signal for AAC.

---

## Required env vars / secrets

Stored in `apple/` keychain bundle (NOT in git):

```
SINGULAR_API_KEY = <from Singular dashboard>
SINGULAR_SECRET  = <from Singular dashboard>
```

ASA credentials live in Singular dashboard, not the app.

---

## Validation checklist (before launching ads)

Run through this in order. Don't launch until every box is checked.

- [ ] Singular SDK initialized — verify with Singular's "Test Console"
      (sends test install + custom event from a real device)
- [ ] `first_share` fires when bundle upload completes — test in TestFlight
      build, verify event in Singular dashboard within 5 min
- [ ] ASA Attribution API connected — Singular shows "Connected" green pill
- [ ] Meta App Events connected — Singular shows "Connected" green pill +
      Meta Events Manager shows the app
- [ ] SKAN conversion model published in Singular and synced to App Store
      Connect (verify in ASC → Your App → App Information → SKAdNetwork)
- [ ] Test install via Singular's test link — confirm attribution appears
      within 2 hours

---

## What you're NOT setting up (and why)

- ❌ **AppsFlyer/Adjust** — Singular Free covers it
- ❌ **Branch deep links** — your share links are already Universal Links
  from `fastsha.red`; Branch would duplicate that infra
- ❌ **GA4 Firebase** — overkill for measurement; Singular reports CPI/CPA
  per channel, which is what we need
- ❌ **Server-side CAPI for Meta** — already covered by Singular's
  Meta App Events relay
- ❌ **TikTok Events API** — not running TikTok ads
- ❌ **Apple Privacy Manifest concerns** — Singular ships a compliant
  manifest; verify their version matches iOS 17+ requirement at install
  time

---

## Cost ceiling on Singular Free

If you exceed Singular's free tier (50k attributions/mo) you're already at
~100x the current spend level — at that point, paid MMP discussions are
warranted. Until then: free tier indefinitely.

---

## Phase 1 dashboards to build in Singular

1. **CPI by source** — ASA-Brand vs ASA-Category vs ASA-Discovery vs Meta
2. **CPI by creative** — for Meta (3 angles)
3. **Install → first_share** funnel — by source
4. **Day 1 / Day 7 retention** — by source (Singular cohorts)

Set these up week 1. Review every Friday during Phase 1.
