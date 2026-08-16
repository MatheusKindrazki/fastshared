# FastShared Pro — launch sequence

6-week playbook from code-complete to launch day. Reference docs in
`docs/marketing/` for the content at each beat.

## Week 1–2 — Backend + Apple implementation

- Plan A lands: IAP webhook, StoreKit verification, tier cap enforcement,
  subscriptions table. CI green on `main`.
- Plan B lands: StoreKit 2 product fetch, paywall UI, receipt submit,
  CloudKit sync. CI green on `main`.
- Plan C (this plan) merges: pricing page, legal updates, ASC runbook
  executed end-to-end.
- Gate: all 3 plans tagged `pro-gate-ready`.

## Week 3 — QA + TestFlight closed beta

- Push a TestFlight build including Pro to a closed group of 50–100
  Pro-interested testers (source from existing TestFlight list plus
  landing-page email signups).
- Run sandbox-purchase flow on each of the 3 tiers. Verify server
  notifications arrive, entitlements flip within 60 s.
- Refund one sandbox purchase per tier. Verify revocation within 5 min.
- Bug triage. No P1 bug uncaught enters Week 4.

## Week 4 — Public landing + App Store metadata go live

- Merge Plan C's web branch to `main`; Cloudflare Pages auto-deploys.
- Verify https://fastsha.red/pricing is live, sitemap includes it,
  schema.org Product markup validates clean.
- Update App Store metadata per `docs/marketing/app-store.md`:
  - Subtitle (if switching to Pro-aware variant)
  - Promotional text: v4 Pro-launch variant
  - Description: v1.1 with Pro section
  - Keywords: v1.1 Pro pack (7-day hold from this point before next
    rotation)
  - What's New in Version 1.1.0

## Week 5 — App Store Review submission

- Submit v1.1 binary with Pro IAPs attached.
- Review notes:
  > Pro unlocks unlimited uploads, 30-day retention, and cross-device
  > history sync via iCloud private database. Free tier unchanged.
- Sandbox test account: `sandbox-review+v1@fastsha.red`.
- Expect 24–72 h review. Respond to any reviewer questions same-day.

## Week 6 — Launch day

- Morning (Pacific, 00:01 PT): release v1.1 via "Release this version
  manually" → Release.
- Product Hunt post at 00:01 Pacific — reuse
  `docs/marketing/launch-producthunt.md` with an added line about Pro +
  Early Access.
- Hacker News "Show HN" at ~09:00 Eastern — reuse
  `docs/marketing/launch-hn.md`, lead with "FastShared Pro is out; free
  tier unchanged; here's what Pro adds."
- Twitter thread at ~10:00 Eastern — reuse
  `docs/marketing/launch-thread-twitter.md` with a final tweet about Early
  Access Lifetime + a countdown to the closing date.
- Monitor: App Store Connect Analytics, Cloudflare Workers logs,
  subscription webhook activity. Any P1 regression → rollback binary
  (ASC "Remove from sale") and patch.

## Post-launch (D+7, D+14, D+30, D+90)

- ASO measurement per `docs/marketing/aso-keywords.md` (Pack B/C/D
  rotation if Pro pack underperforms).
- Churn signal review on Monthly (Apple reports first-month retention
  at D+30).
- Early Access Lifetime window closes at D+90 (3 months from launch) →
  flip price to standard, update `/pricing`, `docs/marketing/app-store.md`,
  and internal dashboards. Communicate the window end-date inside the app
  and on the landing page in Week 5; no last-minute surprises.
