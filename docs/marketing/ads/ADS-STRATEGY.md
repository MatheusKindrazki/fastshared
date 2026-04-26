# FastShared — Paid Ads Strategy

**Last updated:** 2026-04-26
**Owner:** Matheus Kindrazki
**Status:** Plan v1 — pre-launch

---

## Reality check

| Item | Value |
|---|---|
| Monthly budget | **R$ 300** (~US$ 60) |
| Industry benchmark min | US$ 5,000+/mo (Meta + UAC viable floor) |
| Gap | **~83x below "industry minimum"** |

This is not a "scale paid acquisition" plan. This is a **signal-buying plan**:
spend R$ 300/mo to learn which channel/creative/geo converts iOS installs at
acceptable CPI before committing more capital. Treat ads as a **measurement
tool**, not a growth engine, until activation/retention data justifies scale.

---

## Goal stack

1. **Primary (months 1–3):** drive installs to free, no-limit iOS app —
   validate creative angles and CPI ranges.
2. **Secondary:** activation = **first share completed** (event sent to MMP).
3. **Anti-goal:** vanity installs that never share. Algorithm must optimize
   for `first_share`, not `install`.

---

## Geo phasing (forced by budget math)

R$ 300 ÷ 3 markets = R$ 100/market = below learning threshold everywhere.
So we phase:

| Phase | Months | Geo | Budget |
|---|---|---|---|
| 1 | 1–2 | **BR only** | 100% (R$ 300) |
| 2 | 3 | BR + **US** (test) | 60% BR / 40% US |
| 3 | 4+ | BR + US + **EU** | 40 / 40 / 20 |

Phase 2 only triggers if Phase 1 hits **CPI < R$ 5** and **activation rate
> 30%**. Otherwise, fix creative/targeting first.

---

## Platform selection

Cut list (why not):
- **Google App Campaigns (UAC)** — needs ~50 conv/week to exit learning;
  R$ 300/mo can't feed it. Skip.
- **TikTok Ads** — minimum CBO budgets eat full monthly spend in one ad
  group. Skip.
- **LinkedIn / Microsoft / Apple Ads (non-ASA)** — irrelevant for consumer
  iOS file utility.

Active list:

| Platform | Role | Budget % | Rationale |
|---|---|---|---|
| **Apple Search Ads (ASA)** | Primary | 60% (R$ 180) | Bottom-funnel, App Store intent, native iOS attribution, no SDK needed |
| **Meta (Reels/Stories)** | Secondary | 40% (R$ 120) | Top-funnel discovery; gesture/speed creative shines on vertical video |

ASA gets the larger share because intent is already qualified ("user is
searching the App Store"). Meta is for awareness — the product's core gesture
(swipe → share → vanish) reads natively in vertical video.

---

## Creative thesis

Voice locked in `docs/marketing/voice-tone.md`: **Confident · Minimal · Poetic.**

Three angles to test in Phase 1:

1. **Vanish** — "Share anything. Get a link. Watch it vanish."
   Format: 9:16 screen recording, 8s, no music, just gesture + countdown.
2. **By design** — "Every link expires. Every file is deleted. By design."
   Format: text-on-black, 6s, slow type-on, single ambient note.
3. **Speed** — "Faster than email. Smaller than Drive."
   Format: side-by-side comparison, 12s, real iOS share sheet.

One winner emerges by week 4. Kill the other two.

---

## Success criteria (Phase 1 exit gate)

To unlock Phase 2 (US expansion):

- ✅ CPI ≤ **R$ 5** (≈ US$ 1) across both platforms blended
- ✅ Install → first_share rate ≥ **30%**
- ✅ Day 7 retention ≥ **15%** (cohort tracked in Singular)
- ✅ At least **1 creative** per platform with CTR > category median

If 3+ criteria fail, **don't expand geo** — iterate creative on BR first.

---

## What this plan deliberately does NOT do

- No Google UAC (budget too low — wastes spend on learning phase)
- No TikTok (minimum budgets don't fit)
- No retargeting yet (no install base to retarget)
- No iOS+macOS combo (macOS has no paid ad surface; macOS comes later organic)
- No paid MMP (Singular Free covers it)
- No video production budget — first creatives are screen recordings + Capcut

---

## Documents in this folder

- `CAMPAIGN-ARCHITECTURE.md` — exact campaign/ad-group structure + naming
- `BUDGET-PLAN.md` — month-by-month allocation and pacing
- `CREATIVE-BRIEF.md` — production specs for 3 creative angles
- `TRACKING-SETUP.md` — Singular Free + ASA Attribution + Meta SKAN 4.0 setup
- `IMPLEMENTATION-ROADMAP.md` — week-by-week launch plan
