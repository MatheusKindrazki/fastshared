# FastShared — path to recurring revenue (Nov 2026)

Status: proposal ratified by a four-agent review (Claude as judge; Codex, Gemini and Grok as product, market and distribution reviewers). Not yet approved or started by the founder. Detailed evidence, production metrics and per-round transcripts are kept privately, not in this public repository.

## Why change direction

The Pro tier of the Apple utility has been live since 2026-10-25 and has not converted. Usage is occasional, the median shared file is small, and the free tier already covers it. The utility competes with AirDrop, iCloud links and free hosts, so it lacks the weekly habit that a subscription needs. Price changes alone will not fix that.

Two alternative wedges were evaluated and rejected:

- **Images in GitHub PR comments (CI and coding agents).** GitHub now ships `gh pr comment --attach` ([docs](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli)) and browser-viewable non-zipped artifacts ([changelog](https://github.blog/changelog/2026-02-26-github-actions-now-supports-uploading-and-downloading-non-zipped-artifacts/)). The remaining gap, `--attach` failing with app installation tokens ([cli/cli#14309](https://github.com/cli/cli/issues/14309)), is one that GitHub is actively closing. Argos already sells CLI, MCP and managed PR comments for agent media ([Argos Media Sharing](https://argos-ci.com/media-sharing)). The platform risk is too high.
- **Secure document exchange for accountants and law firms.** Willingness to pay is real, but it requires consultative sales, local invoicing and compliance work. That does not fit a solo founder with about 10 hours a week.

## Decision

**Positioning:** "Send the link. Your iPhone tells you when the client opens it."
Sub-line: publish the report, proposal or prototype your AI made as a live link; update it without changing the URL; revoke it when you want.

**Ideal customer:** a freelancer or consultant (data, QA, dev, design) who sends a client an HTML, PDF or ZIP built with Claude, Codex, Cursor or ChatGPT every week, and today does not know whether it was read.

**Why they would pay us instead of a free host:**

- [sharable.link](https://sharable.link/) is free and already offers passwords, versions and revocation. It does not identify visitors or notify the sender ([privacy](https://sharable.link/privacy)).
- tiiny.host alerts on opens only from its Solo plan at US$18/month ([pricing](https://helpdesk.tiiny.host/en/article/pricing-plans-1i3vkky/)).
- DocSend Personal costs about US$15 per user per month.

FastShared already sends an APNs push when a link is opened. The differentiator is an open alert that is reliable and arrives on the phone, and it reuses code that already exists.

**Entry points:** web drag-and-drop uploader, CLI and a thin MCP wrapper. The iOS and Mac apps receive the alerts and give Mac users a fast way to send. Publishing straight from the Claude or ChatGPT iOS share sheet is **not** promised; it ships only if a compatibility test passes.

## Plans

| | Free | Pro |
|---|---|---|
| Price | US$0 | **US$15/month or US$144/year** |
| Active publications | 1 | Within a storage quota (2 GB) |
| Lifetime | Expires after 7 days | Kept while the subscription is active |
| Badge | "Hosted with FastShared" | None |
| Open alerts | Limited (proposal: 3) | Unlimited, per version |
| Same-URL versions, password, analytics | No | Yes |

There is no Team plan until customers ask for one. The existing App Store tiers stay as they are during this cycle.

**Retention rule.** The `/s/` links stay ephemeral, as they are today. A new surface, *publications*, gets its own lifecycle:

- Free publications expire after 7 days.
- Pro publications live while the subscription is active.
- On cancellation, the founder gets 30 days of notice and export, then the files are deleted.
- The owner can revoke at any time.

There are no immortal, ownerless links.

## Targets (all estimates)

| Month | MRR range |
|---|---|
| 4 | US$100–200 |
| 9 | US$350–750 |
| 12 | US$500–1,400 |

Reaching US$2,000 MRR by month 12 needs about 133 Pro subscribers. The reviewers put the probability at **5–15%**. The upside comes from the slow, compounding SEO and badge loop that grew tiiny.host from about US$600 MRR at month 20 to more than US$20k MRR ([case study](https://superframeworks.com/case-study/tiiny-host)). That is why SEO starts early and runs in parallel.

## Go-to-market

1. **Weeks 1–12: build the sellable slice** (see `mrr-backlog.md`). From week 4, publish one SEO page per week targeting purchase-intent queries:
   - share html file as link
   - share claude artifact with client
   - track when client opens link
   - docsend alternative for html reports
   - host interactive html dashboard
   - password protected html link
2. **Before launch:** 10 invited pilots from the founder's network use it on real client sends.
3. **Launch (around week 16):**
   - Show HN titled "My iPhone pings when a client opens the proposal Claude just wrote".
   - One post in r/freelance or r/consulting, where self-promotion rules allow it.
   - Five direct messages a week, only to people who complained in public about not knowing whether a client read their material.
4. **Out of scope this cycle:** paid ads, Product Hunt, Setapp, AppSumo, and tightening the free tier of the Apple app.

## Kill gates

Founder devices are excluded from every count.

| When | Pass condition | If it fails |
|---|---|---|
| End of week 3, before any P1 work | Open alerts fire with no false positives when the link is pasted into WhatsApp, Slack and iMessage, and user HTML is served off the main domain | Drop the thesis |
| Week 8 | At least 6 of the 10 pilots published more than once, and at least 2 say they would pay US$15 | Stop before building billing |
| Launch + 45 days | At least 10 external users republished | Back to personal tool |
| Launch + 90 days | At least 5 paying customers | Back to personal tool |

## Recorded risks

- A JavaScript beacon proves that a real browser rendered the page, not that a specific client did. Alert copy must say "opened in a browser" until recipient verification exists.
- Until month 6, revenue depends on pilots and direct outreach. SEO and the badge take 6–12 months to compound.
- Hosting user HTML attracts phishing. Origin isolation, reporting and takedown are launch blockers, not follow-ups.
