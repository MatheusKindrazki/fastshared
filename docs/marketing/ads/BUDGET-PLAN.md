# FastShared — Budget Plan

**Total monthly:** R$ 300 (~US$ 60)

---

## Phase 1 — BR only (months 1–2)

| Channel | Campaign | Daily | Monthly |
|---|---|---:|---:|
| ASA | Brand | R$ 1.50 | R$ 45 |
| ASA | Category | R$ 3.00 | R$ 90 |
| ASA | Discovery | R$ 1.50 | R$ 45 |
| Meta | AAC-Prospecting BR | R$ 4.00 | R$ 120 |
| **Total** | | **R$ 10.00** | **R$ 300** |

---

## Phase 2 — BR + US (month 3, conditional)

Trigger: Phase 1 exit gate passed (CPI ≤ R$ 5 + first_share ≥ 30%).

| Channel | Campaign | Daily | Monthly |
|---|---|---:|---:|
| ASA | Brand BR | R$ 1.00 | R$ 30 |
| ASA | Category BR | R$ 2.00 | R$ 60 |
| ASA | Category US (NEW) | R$ 2.00 | R$ 60 |
| ASA | Discovery US (NEW) | R$ 1.00 | R$ 30 |
| Meta | AAC BR | R$ 2.30 | R$ 70 |
| Meta | AAC US (NEW) | R$ 1.70 | R$ 50 |
| **Total** | | **R$ 10.00** | **R$ 300** |

ASA shifts toward US (Category US > Category BR) because US CPI is higher
and we need enough budget to clear the auction floor in that market.

---

## Phase 3 — BR + US + EU (month 4+, conditional)

Trigger: Phase 2 sustains CPI ≤ US$ 3 in US for 4 consecutive weeks.

| Channel | Campaign | Monthly |
|---|---|---:|
| ASA | Category BR | R$ 50 |
| ASA | Category US | R$ 60 |
| ASA | Category EU (NEW, English-speaking only: UK + IE) | R$ 50 |
| Meta | AAC BR | R$ 50 |
| Meta | AAC US | R$ 50 |
| Meta | AAC UK (NEW) | R$ 40 |
| **Total** | | **R$ 300** |

EU = UK + Ireland only. Skip non-English EU (DE/FR/ES/IT) until creative
is localized — running English ads in non-English markets wastes spend.

---

## Pacing rules

- **Daily cap = monthly ÷ 30**, not weekly. Weekly caps create end-of-week
  starvation when ASA's auction is hottest (Friday–Sunday).
- **Pause spend on day 28 of month** if ≥90% of monthly budget already
  consumed — ASA in particular can blow through caps when impression share
  spikes.
- **Reallocation cadence:** once per week, max 20% shift between campaigns.
  No more — kills learning.

---

## Kill rules (mandatory, from the skill's quality gates)

| Rule | Action |
|---|---|
| **3x Kill Rule** — campaign CPA > 3× target CPA for 7 days | Pause |
| Ad group with 0 conversions after R$ 50 spend | Pause |
| Creative with CTR < 0.5% after 3000 impressions (Meta) | Pause |
| Keyword with 50+ taps and 0 installs (ASA) | Add as negative |

Target CPI: R$ 5 → 3× = R$ 15 = pause threshold per campaign.

---

## What R$ 300/mo actually buys (honest math)

Assuming hit rates aligned with industry benchmarks:

| Scenario | Blended CPI | Installs/mo | First shares/mo |
|---|---:|---:|---:|
| Pessimistic | R$ 8 | 38 | 11 |
| Realistic | R$ 5 | 60 | 18 |
| Optimistic | R$ 3 | 100 | 30 |

Even the optimistic case produces ~30 activated users/mo. That's enough to
**measure**, not enough to **scale**. The plan is correct only if you
read it as: *we're paying R$ 300/mo for data, not for users.*

If after month 2 the numbers don't validate, the next conversation isn't
"scale ads" — it's "fix product/market fit before spending more."
