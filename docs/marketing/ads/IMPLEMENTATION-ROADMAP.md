# FastShared — Ads Implementation Roadmap

12-week plan, week-by-week. Don't skip weeks — each gate matters.

---

## Week 1 — Tracking foundation (NO ADS YET)

| Day | Task | Owner | Output |
|---|---|---|---|
| 1 | Sign up Singular Free + create iOS app entry | Matheus | Dashboard access, API key |
| 1–2 | Add Singular SDK to `apple/` (SwiftPM) | iOS dev | PR merged to main |
| 2 | Implement `first_share` event call at upload completion | iOS dev | Event verified in TestFlight |
| 3 | Configure SKAN conversion model in Singular dashboard | Matheus | Model published |
| 3 | Connect ASA Attribution API in Singular | Matheus | Green status |
| 4 | Connect Meta App Events in Singular | Matheus | Green status, app shows in Meta Events Manager |
| 5 | Run validation checklist (see TRACKING-SETUP.md) | Matheus | All boxes checked |

**Gate to Week 2:** every checkbox in TRACKING-SETUP.md validation list
must be green. Do not proceed if any are red. Burning R$ 300 with broken
attribution = burning R$ 300 you'll never get back as data.

---

## Week 2 — Creative production

| Day | Task | Output |
|---|---|---|
| 1–2 | Record Angle A (Vanish) — screen capture + cuts | `creative/meta/vanish-9x16-v1.mp4` |
| 2–3 | Record Angle B (By design) — text/audio | `creative/meta/bydesign-9x16-v1.mp4` |
| 3–4 | Record Angle C (Speed) — split-screen | `creative/meta/speed-9x16-v1.mp4` |
| 4 | Design Speed CPP screenshots (4 frames) | `creative/asa/speed-cpp/*.png` |
| 5 | Design Privacy CPP screenshots (4 frames) | `creative/asa/privacy-cpp/*.png` |
| 5 | Upload CPPs in App Store Connect | CPPs published |

**Tooling:** QuickTime + CapCut (free) for video. Figma for CPP frames.
No outsourcing. **4-hour cap per angle** — over-polish is the enemy.

---

## Week 3 — Soft launch (ASA only, brand defense)

Why ASA-only first: cheapest learning path, highest intent.

| Day | Task |
|---|---|
| 1 | Create ASA campaigns in App Store Connect (Brand + Category + Discovery) |
| 1 | Set bids per CAMPAIGN-ARCHITECTURE.md, daily caps from BUDGET-PLAN.md |
| 1 | Attach Speed CPP and Privacy CPP to relevant ad groups |
| 2–7 | Monitor daily. **Do not touch bids for 7 days** — let learning happen |

**End-of-week-3 review:** look only at:
- Total taps per campaign
- CPT trending up or down
- Singular dashboard showing first_share events from ASA-attributed installs

**Don't optimize yet.** Even a bad week 3 is just data.

---

## Week 4 — Meta launch

| Day | Task |
|---|---|
| 1 | Create Advantage+ App Campaign in Meta Ads Manager |
| 1 | Upload 3 video creatives (Vanish + By design + Speed) |
| 1 | Set optimization event = `app_install` (NOT first_share yet — too few events) |
| 1 | Daily budget R$ 4 |
| 2–7 | Monitor. **Do not pause any creative for 7 days.** Let Meta's algorithm find which creative gets impressions |

**End-of-week-4 review:**
- Did at least one creative emerge with CTR > 1%?
- Is CPI in Meta below R$ 8?
- Is the install → first_share rate visible in Singular yet?

---

## Weeks 5–6 — First optimization pass

Now you have ~14 days of data per channel. Allowed actions:

1. **Pause** ASA keywords with 50+ taps and 0 installs (add as negatives)
2. **Pause** Meta creative with CTR < 0.5% after 3000 impressions
3. **Promote** ASA Discovery keywords with conversion → move to Category
   campaign as Exact match
4. **No bid changes** > 20% in either direction

**End-of-week-6 milestone:**
Compute blended CPI and first_share rate. Compare to Phase 1 exit gate
(CPI ≤ R$ 5, first_share ≥ 30%, D7 retention ≥ 15%).

If gate fails: **iterate creative for weeks 7–8 before any geo expansion.**
If gate passes 50–70%: stay in Phase 1, refine.
If gate passes ≥80%: prep Phase 2.

---

## Weeks 7–8 — Iterate or prep expansion

**Path A — gate failed or partially failed:**
- Replace 2 of 3 Meta creatives with new variants (test new angle)
- Audit ASA keyword list — likely too narrow, add 10 broader category terms
- DO NOT add geos. Fix BR first.

**Path B — gate passed:**
- Translate 2 winning creatives to English
- Build US Custom Product Page in App Store Connect
- Plan ASA US storefront keywords (different search behavior — research
  before launching, don't just translate BR keywords)

---

## Weeks 9–10 — Phase 2 launch (US, conditional)

If Path B was taken in week 8:

| Day | Task |
|---|---|
| 1 | Reallocate budget per BUDGET-PLAN.md Phase 2 table |
| 1 | Launch ASA US Category + Discovery campaigns |
| 1 | Launch Meta AAC US campaign (separate from BR — never combine geos in one AAC) |
| 2–14 | Standard learning period — no touch for 7 days |

If Path A: keep refining BR. Phase 2 slips to month 4.

---

## Weeks 11–12 — Steady state + reporting

| Activity | Cadence |
|---|---|
| Friday review meeting (with yourself) | Weekly |
| Creative refresh (replace lowest CTR ad) | Bi-weekly |
| Keyword mining from ASA Discovery | Weekly |
| Negative keyword sweep | Weekly |
| Bid tuning (max ±20%) | Weekly |
| Full performance report (per-channel CPI/CPA/retention) | Monthly |

---

## Decision tree at month 3 end

```
Phase 1 + Phase 2 results
│
├── Blended CPI ≤ R$ 5 AND first_share ≥ 30% AND D7 retention ≥ 15%
│   └── Phase 3 (BR + US + UK), consider 2x budget to R$ 600/mo
│
├── CPI 5–10 OR retention 10–15%
│   └── Hold at R$ 300/mo, iterate creative for another month before
│       expanding geo
│
└── CPI > R$ 10 OR retention < 10%
    └── PAUSE all paid acquisition. The signal is "product not ready" or
        "wrong audience." Spending more won't fix it. Reinvest the R$ 300
        in product/onboarding work for 1 month, then re-test.
```

The third branch is the most important one to take seriously. Most R$ 300
plans fail on creative or product fit, not budget — and the R$ 300 you
*don't* spend on a failing channel is the most valuable R$ 300 in this
plan.
