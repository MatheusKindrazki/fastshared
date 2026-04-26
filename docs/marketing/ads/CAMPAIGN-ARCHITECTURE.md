# FastShared — Campaign Architecture

## Naming convention

```
[Platform]_[Objective]_[AdGroup-or-Audience]_[Geo]_[YYMM]
```

Examples:
- `ASA_INSTALL_Brand_BR_2604`
- `ASA_INSTALL_Category-FileShare_BR_2604`
- `META_INSTALL_Reels-Vanish-Lookalike1_BR_2604`

---

## Apple Search Ads (ASA) — R$ 180/mo

ASA splits its spend across 4 standard campaign types. With R$ 180/mo, we run
**3 of 4** to keep each above its learning threshold.

```
Apple Search Ads — fastshared (BR storefront)
│
├── ASA_INSTALL_Brand_BR_2604         [25% — R$ 45/mo]
│   Match: Exact
│   Keywords: fastshared, fast shared, fast share
│   Bid: CPT R$ 0.40 (defensive — protect brand from competitor squat)
│
├── ASA_INSTALL_Category_BR_2604       [50% — R$ 90/mo]
│   Match: Exact + Search Match ON
│   Keywords (exact, seed list):
│     - compartilhar arquivo
│     - enviar arquivo grande
│     - link temporário
│     - wetransfer alternativa
│     - transferir arquivo iphone
│   Bid: CPT R$ 0.80 (start) → tune to CPA goal R$ 5
│
└── ASA_INSTALL_Discovery_BR_2604      [25% — R$ 45/mo]
    Match: Broad + Search Match ON
    Keywords: same seed list, broad
    Purpose: KEYWORD MINING ONLY — promote winners to Category weekly
    Bid: CPT R$ 0.50 (low — we're paying for learning)
```

**Skip for now:** `Competitor` campaign. WeTransfer/Send Anywhere brand
defense is a phase 2 problem; we don't have the budget to attack their
brand traffic profitably.

**Custom Product Pages (CPP):** create 1 CPP per category keyword cluster.
Minimum: a "speed" CPP (gesture-forward screenshots) and a "privacy" CPP
(expiry/vanish-forward screenshots). Match CPP to ad group, not campaign.

---

## Meta Ads — R$ 120/mo

One **Advantage+ App Campaign (AAC)**. Don't fragment — Meta's algorithm
needs concentrated signal at low budgets.

```
Meta — fastshared (iOS)
│
└── META_INSTALL_AAC-Prospecting_BR_2604   [100% — R$ 120/mo]
    Type: Advantage+ App Campaign
    Optimization event: app_install (Phase 1) → first_share (Phase 2, once
                       MMP shows >50 first_share events/wk)
    Audience: Broad BR, age 18–44, iOS only
    Placements: Reels + Stories ONLY (no Feed — vertical-native)
    Daily budget: R$ 4/day
    Bid: Lowest Cost (no cap — let Meta find floor)
    Creative pool: 3 videos (one per angle: Vanish / By design / Speed)
```

**Why one campaign, one ad set:** at R$ 4/day, fragmenting kills learning.
AAC's automation expects ≥50 events/week; we'll be below that, but at least
all signal goes to one model.

**Exclusions:** existing app users (device-based custom audience, configured
post-launch once we have install data).

---

## What we explicitly DO NOT build (yet)

| Structure | Why not now | When to add |
|---|---|---|
| Google UAC | Below learning threshold | Phase 3+, when budget ≥ R$ 1500/mo |
| Retargeting | No install base | Month 2+, when DAU > 500 |
| Re-engagement (lapsed) | No lapsed users | Month 3+ |
| Lookalike audiences | Need ≥1k seed users | Month 3+ |
| Value optimization (ROAS) | Free app, no revenue events | When freemium tier ships |

---

## Phase 2 changes (BR + US, month 3)

If exit gate passes:

```
ASA: clone Category + Discovery for US storefront
     New campaigns: ASA_INSTALL_Category_US_2606, ASA_INSTALL_Discovery_US_2606
     Reuse keyword logic, translated. NEW CPP in English.

Meta: split AAC by geo
      META_INSTALL_AAC-Prospecting_BR_2606  (R$ 70/mo)
      META_INSTALL_AAC-Prospecting_US_2606  (R$ 50/mo)
```

Geo split happens at the **campaign level**, never ad-set level — Meta
explicitly recommends one country per AAC for cleaner attribution.
