# FastShared Pro — Plan C (Launch Prep)

> **For Agents:** REQUIRED SUB-SKILL: Use ring:executing-plans to implement this plan task-by-task.

**Goal:** Ship the public-facing launch surfaces for FastShared Pro — pricing page, legal updates, marketing doc refresh, and the App Store Connect manual runbook — so that the Pro launch has complete copy, legal coverage, and a reproducible store configuration on launch day.

**Architecture:** Extend the existing Astro + Tailwind landing at `web/` with a new `/pricing` route and three-tier comparison table, extend `privacy.astro` and `terms.astro` with subscription + CloudKit sections, refresh the marketing docs in `docs/marketing/` to add Pro copy, and produce an App Store Connect manual checklist covering 3 IAP products, server notifications, and key generation. Backend (Plan A) and Apple client (Plan B) are executed in parallel — this plan does not touch them.

**Tech Stack:** Astro 4 (static), Tailwind CSS, existing `Base.astro` layout, `@astrojs/sitemap`. Marketing docs are plain markdown. App Store Connect is a manual web UI — no automation.

**Scope boundary:** This plan covers ONLY Parts 1–8 below. Backend Workers, Durable Objects, KV, Neon migrations → Plan A. Apple client StoreKit 2, paywall UI, CloudKit sync → Plan B. Upload compression is explicitly rejected and not in any plan.

**Global Prerequisites:**
- Plan A (backend) and Plan B (Apple) are either in-flight or complete — the webhook URL and product IDs referenced here MUST match what Plan A builds and Plan B consumes.
- Environment: macOS with Node 20+, pnpm 8+, git, access to the `fastshared` repo on `main`.
- Tools: `pnpm --version` ≥ 8, `node --version` ≥ 20, `git --version` ≥ 2.40, a modern browser for App Store Connect (Safari preferred for Apple UIs).
- Access: App Store Connect account with Admin or App Manager role for FastShared. Apple Developer account with agreements signed (Paid Apps Agreement MUST be active — without it, IAP products cannot be created).
- State: Work on a fresh branch `feat/pro-launch-C`, branched from `main`.

**Verification before starting:**

```bash
# Run ALL these commands and verify output:
cd /Users/matheuskindrazki/development/crazy-ideas/fastshared
git status                              # Expected: clean working tree on main
node --version                          # Expected: v20.x or higher
pnpm --version                          # Expected: 8.x or higher
cd web && pnpm install                  # Expected: Dependencies installed without errors
pnpm build                              # Expected: Astro build succeeds, generates dist/ with sitemap-index.xml
pnpm dev                                # Expected: Dev server on http://127.0.0.1:4321 (Ctrl-C to exit)
```

Also confirm with the product owner BEFORE starting any `[CONFIRM]` task:
- [ ] Early Access Lifetime window: start date + end date (suggested: 30 days from launch)
- [ ] Family Sharing rules: Lifetime = ON, Monthly/Annual = OFF (needs owner sign-off)
- [ ] No introductory offers / free trial for v1 (already decided — confirm nothing changed)
- [ ] Pricing: $2.99 / $19.99 / $49.99 in USD, Apple auto-managed localisation ON
- [ ] App Store regions: ALL (no exclusions)
- [ ] Tax category: Software utility (confirm with accountant if any doubt)

---

## Task ID Legend

- `C1.x` — Part 1: Pricing page
- `C2.x` — Part 2: Landing page updates
- `C3.x` — Part 3: Privacy policy updates
- `C4.x` — Part 4: Terms of Service updates
- `C5.x` — Part 5: Marketing docs
- `C6.x` — Part 6: Product overview
- `C7.x` — Part 7: App Store Connect runbook
- `C8.x` — Part 8: Launch sequencing

Parallel-safe tasks are marked `[parallel]`. Dependencies are noted inline.

---

## Part 1 — Pricing page on fastsha.red

### Task C1.1: Create pricing page skeleton [parallel-safe]

**Files:**
- Create: `web/src/pages/pricing.astro`

**Prerequisites:** None. Independent from all other tasks.

**Step 1: Create the file with Base layout, Nav, Footer, and a placeholder `<main>`.**

```astro
---
import Base from '../layouts/Base.astro';
import Nav from '../components/Nav.astro';
import Footer from '../components/Footer.astro';
---
<Base
  title="Pricing — FastShared"
  description="FastShared Pro unlocks unlimited uploads, 30-day link retention, and iCloud history sync. Free stays free. Pro from $2.99/mo."
>
  <Nav />
  <main class="frame pt-16 pb-24 max-w-[1080px] mx-auto">
    <!-- Pricing content tasks C1.2 → C1.6 populate this -->
  </main>
  <Footer />
</Base>
```

**Step 2: Verify by running `cd web && pnpm dev` and opening `http://127.0.0.1:4321/pricing`.**

**Expected output:** Blank dark-themed page with Nav + Footer. No console errors.

**If it fails:** Run `pnpm astro check` to see TypeScript/Astro errors. Most likely cause: filename typo or missing import.

---

### Task C1.2: Write the hero section for pricing page

**Files:**
- Modify: `web/src/pages/pricing.astro` (inside `<main>`)

**Prerequisites:** C1.1 complete.

**Step 1: Add this block inside `<main>` after the opening tag.**

```astro
<section class="pt-8 md:pt-12 pb-12 md:pb-16">
  <p class="font-mono text-[12px] tracking-[0.18em] uppercase text-amber mb-6">
    01 / pricing
  </p>
  <h1
    class="font-display font-bold text-milk"
    style="font-size: clamp(48px, 9vw, 128px); line-height: 0.92; letter-spacing: -0.055em;"
  >
    <span class="block">One gesture.</span>
    <span class="block">One link.</span>
    <span class="block italic text-coral">Your call on the rest.</span>
  </h1>
  <p class="mt-8 font-mono text-[14px] leading-[1.6] tracking-[0.03em] text-milk/55 max-w-[640px]">
    Free is honest. Pro is generous. No dark patterns, no feature-gated anti-virus, no "unlock export" nonsense — just higher ceilings, longer retention, and iCloud sync for the people who share every day.
  </p>
</section>
```

**Step 2: Verify at `/pricing`. Expected:** Hero renders with brand amber/coral accents, Bricolage Grotesque, matching the rest of the site's aesthetic.

---

### Task C1.3: Write the 3-tier comparison table (desktop)

**Files:**
- Modify: `web/src/pages/pricing.astro`

**Prerequisites:** C1.2 complete.

**Intent:** A 4-column grid (Free, Pro Monthly, Pro Annual, Pro Lifetime) with feature rows: uploads per day, max file size, link retention, cross-device sync (iCloud), revoke & history, priority support, Family Sharing. Amber accent on Pro tier headers, coral "Early Access" ribbon on Lifetime, "save ~45%" amber badge on Annual.

**Step 1: Add the table section to `<main>`.**

```astro
<section class="pb-16" aria-labelledby="tiers-heading">
  <h2 id="tiers-heading" class="sr-only">Tier comparison</h2>

  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
    <!-- Free -->
    <article class="tier-card" data-tier="free">
      <header class="tier-head">
        <p class="tier-name">Free</p>
        <p class="tier-price"><span class="amount">$0</span><span class="period">forever</span></p>
        <p class="tier-blurb">For occasional shares. No account, no card.</p>
      </header>
      <a href="#app-store" class="btn-ghost tier-cta" data-testid="cta-free">Start free →</a>
      <ul class="tier-features" aria-label="Free tier features">
        <li><span class="ft-k">Uploads / day</span><span class="ft-v">5</span></li>
        <li><span class="ft-k">Max file size</span><span class="ft-v">100 MB</span></li>
        <li><span class="ft-k">Link retention</span><span class="ft-v">up to 24 h</span></li>
        <li><span class="ft-k">iCloud sync</span><span class="ft-v ft-off">—</span></li>
        <li><span class="ft-k">Revoke & history</span><span class="ft-v">on this device</span></li>
        <li><span class="ft-k">Priority support</span><span class="ft-v ft-off">—</span></li>
        <li><span class="ft-k">Family Sharing</span><span class="ft-v ft-off">—</span></li>
      </ul>
    </article>

    <!-- Pro Monthly -->
    <article class="tier-card tier-pro" data-tier="monthly">
      <header class="tier-head">
        <p class="tier-name">Pro Monthly</p>
        <p class="tier-price"><span class="amount">$2.99</span><span class="period">/ month</span></p>
        <p class="tier-blurb">For regulars. Pause any time.</p>
      </header>
      <a href="#app-store" class="btn-primary tier-cta" data-testid="cta-monthly">Go Pro →</a>
      <ul class="tier-features" aria-label="Pro Monthly features">
        <li><span class="ft-k">Uploads / day</span><span class="ft-v">unlimited</span></li>
        <li><span class="ft-k">Max file size</span><span class="ft-v">2 GB</span></li>
        <li><span class="ft-k">Link retention</span><span class="ft-v">up to 30 days</span></li>
        <li><span class="ft-k">iCloud sync</span><span class="ft-v ft-on">included</span></li>
        <li><span class="ft-k">Revoke & history</span><span class="ft-v ft-on">across devices</span></li>
        <li><span class="ft-k">Priority support</span><span class="ft-v ft-on">included</span></li>
        <li><span class="ft-k">Family Sharing</span><span class="ft-v ft-off">—</span></li>
      </ul>
    </article>

    <!-- Pro Annual -->
    <article class="tier-card tier-pro" data-tier="annual">
      <header class="tier-head">
        <p class="tier-name">Pro Annual <span class="badge-amber">save ~45%</span></p>
        <p class="tier-price"><span class="amount">$19.99</span><span class="period">/ year</span></p>
        <p class="tier-blurb">For the yearly budget line. Pays for itself in 7 months.</p>
      </header>
      <a href="#app-store" class="btn-primary tier-cta" data-testid="cta-annual">Go Pro →</a>
      <ul class="tier-features" aria-label="Pro Annual features">
        <li><span class="ft-k">Uploads / day</span><span class="ft-v">unlimited</span></li>
        <li><span class="ft-k">Max file size</span><span class="ft-v">2 GB</span></li>
        <li><span class="ft-k">Link retention</span><span class="ft-v">up to 30 days</span></li>
        <li><span class="ft-k">iCloud sync</span><span class="ft-v ft-on">included</span></li>
        <li><span class="ft-k">Revoke & history</span><span class="ft-v ft-on">across devices</span></li>
        <li><span class="ft-k">Priority support</span><span class="ft-v ft-on">included</span></li>
        <li><span class="ft-k">Family Sharing</span><span class="ft-v ft-off">—</span></li>
      </ul>
    </article>

    <!-- Pro Lifetime -->
    <article class="tier-card tier-pro tier-lifetime" data-tier="lifetime">
      <div class="ribbon-coral" aria-hidden="true">Early Access</div>
      <header class="tier-head">
        <p class="tier-name">Pro Lifetime</p>
        <p class="tier-price"><span class="amount">$49.99</span><span class="period">once</span></p>
        <p class="tier-blurb">For the believers. One-time. Family Sharing included.</p>
      </header>
      <a href="#app-store?offer=lifetime" class="btn-primary tier-cta" data-testid="cta-lifetime">Go Lifetime →</a>
      <ul class="tier-features" aria-label="Pro Lifetime features">
        <li><span class="ft-k">Uploads / day</span><span class="ft-v">unlimited</span></li>
        <li><span class="ft-k">Max file size</span><span class="ft-v">2 GB</span></li>
        <li><span class="ft-k">Link retention</span><span class="ft-v">up to 30 days</span></li>
        <li><span class="ft-k">iCloud sync</span><span class="ft-v ft-on">included</span></li>
        <li><span class="ft-k">Revoke & history</span><span class="ft-v ft-on">across devices</span></li>
        <li><span class="ft-k">Priority support</span><span class="ft-v ft-on">included</span></li>
        <li><span class="ft-k">Family Sharing</span><span class="ft-v ft-on">up to 6</span></li>
      </ul>
    </article>
  </div>

  <p class="mt-8 font-mono text-[12px] tracking-[0.06em] text-milk/40">
    Prices in USD. Apple handles localised pricing and taxes. All tiers auto-renew per Apple's standard terms. Cancel any time in iOS Settings → Apple ID → Subscriptions.
  </p>
</section>
```

**Step 2: Verify at `/pricing`.** The 4 cards will initially render unstyled — that's expected. Styling follows in C1.4.

---

### Task C1.4: Add pricing-table styles

**Files:**
- Modify: `web/src/styles/global.css` (append to end of file)

**Prerequisites:** C1.3 complete.

**Step 1: Append this CSS to `web/src/styles/global.css`.**

```css
/* ============================================================
   Pricing page — tier cards
   ============================================================ */
.tier-card {
  position: relative;
  display: flex;
  flex-direction: column;
  padding: 28px 24px 24px;
  background: rgba(29, 13, 75, 0.35);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 18px;
  overflow: hidden;
  transition: transform 220ms cubic-bezier(0.16, 1, 0.3, 1),
              border-color 220ms ease;
}
.tier-card:hover { transform: translateY(-2px); border-color: rgba(255, 159, 71, 0.25); }

.tier-card.tier-pro {
  background: linear-gradient(180deg, rgba(255, 159, 71, 0.08) 0%, rgba(29, 13, 75, 0.5) 100%);
  border-color: rgba(255, 159, 71, 0.25);
}
.tier-card.tier-lifetime { border-color: rgba(255, 78, 124, 0.35); }

.tier-head { margin-bottom: 20px; }
.tier-name {
  font-family: var(--mono);
  font-size: 12px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--milk);
  display: flex; align-items: center; gap: 8px;
}
.tier-price {
  margin-top: 12px;
  font-family: var(--display);
  font-weight: 700;
  color: var(--milk);
  display: flex; align-items: baseline; gap: 8px;
}
.tier-price .amount { font-size: 44px; letter-spacing: -0.04em; }
.tier-price .period {
  font-family: var(--mono);
  font-size: 12px;
  color: rgba(250, 250, 255, 0.5);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.tier-blurb {
  margin-top: 10px;
  font-family: var(--mono);
  font-size: 12px;
  line-height: 1.55;
  color: rgba(250, 250, 255, 0.6);
}

.tier-cta { align-self: flex-start; margin-bottom: 24px; }

.tier-features {
  list-style: none;
  padding: 0;
  margin: 0;
  border-top: 1px solid var(--rule-soft);
}
.tier-features li {
  display: flex; justify-content: space-between; align-items: center;
  padding: 10px 0;
  border-bottom: 1px solid var(--rule-soft);
  font-family: var(--mono);
  font-size: 12px;
  letter-spacing: 0.03em;
}
.ft-k { color: rgba(250, 250, 255, 0.55); }
.ft-v { color: var(--milk); }
.ft-v.ft-on { color: var(--amber); }
.ft-v.ft-off { color: rgba(250, 250, 255, 0.25); }

.badge-amber {
  font-size: 10px;
  letter-spacing: 0.08em;
  padding: 3px 8px;
  border-radius: 999px;
  background: rgba(255, 159, 71, 0.15);
  color: var(--amber);
  border: 1px solid rgba(255, 159, 71, 0.35);
}

.ribbon-coral {
  position: absolute;
  top: 14px; right: -32px;
  transform: rotate(28deg);
  background: var(--coral);
  color: var(--ink);
  padding: 4px 36px;
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  font-weight: 700;
}
```

**Step 2: Verify.** Open `/pricing`. Expected: 4 cards with proper styling, amber glow on Pro, coral "Early Access" ribbon on Lifetime card, feature rows align in two columns (key left, value right), amber highlight on "included"/"unlimited" values.

**If cards render wrong widths on mobile:** Tailwind's `grid-cols-1 md:grid-cols-2 lg:grid-cols-4` handles it. Test with browser devtools at 375px, 768px, 1024px.

---

### Task C1.5: Write the FAQ block (6–8 Q&As)

**Files:**
- Modify: `web/src/pages/pricing.astro`

**Prerequisites:** C1.4 complete.

**Step 1: Add this section after the pricing table.**

```astro
<section class="pt-16 pb-16" aria-labelledby="pricing-faq">
  <header class="mb-10">
    <p class="font-mono text-[12px] tracking-[0.18em] uppercase text-amber">02 / questions</p>
    <h2 id="pricing-faq" class="mt-3 font-display font-semibold text-milk" style="font-size: clamp(32px, 5vw, 56px); letter-spacing: -0.03em;">
      Questions you were about to ask.
    </h2>
  </header>

  <div class="max-w-[780px]">
    <details class="faq-item">
      <summary>Can I get a refund?</summary>
      <div class="faq-body">All refunds go through Apple, not us. Open apple.com/support → Report a Problem, pick the FastShared purchase, and choose a reason. Apple decides. We honour whatever they decide — if they issue a refund, Pro turns off the same day via the App Store Server API.</div>
    </details>
    <details class="faq-item">
      <summary>What auto-renews?</summary>
      <div class="faq-body">Monthly and Annual auto-renew 24 hours before the period ends, per Apple's standard subscription model. Lifetime does not renew — it's a one-time purchase. You can cancel any auto-renew in iOS Settings → Apple ID → Subscriptions; the current period stays active until it ends.</div>
    </details>
    <details class="faq-item">
      <summary>Can I switch between Monthly and Annual?</summary>
      <div class="faq-body">Yes. In iOS Settings → Apple ID → Subscriptions → FastShared Pro, pick the other tier. Apple prorates the difference and switches you on the next billing cycle. Both tiers are in the same subscription group, so you can't hold both at once.</div>
    </details>
    <details class="faq-item">
      <summary>How does Family Sharing work?</summary>
      <div class="faq-body">Lifetime supports Family Sharing — up to 6 family members unlock Pro on their own Apple IDs once the organiser enables it in Settings. Monthly and Annual do not support Family Sharing in v1; each person needs their own subscription.</div>
    </details>
    <details class="faq-item">
      <summary>How do I cancel?</summary>
      <div class="faq-body">iOS Settings → tap your name → Subscriptions → FastShared Pro → Cancel Subscription. No emails, no retention calls, no "are you sure" modals from us. Apple handles the flow end-to-end.</div>
    </details>
    <details class="faq-item">
      <summary>What happens when I downgrade to Free?</summary>
      <div class="faq-body">Existing links keep their original expiry (up to 30 days) — we don't retroactively shorten them. After the subscription lapses, new uploads revert to Free limits: 5/day, 100 MB max, 24 h retention ceiling. iCloud sync stops; records already in your private iCloud stay for 30 days, then iCloud prunes them naturally.</div>
    </details>
    <details class="faq-item">
      <summary>Why $49.99 for Lifetime?</summary>
      <div class="faq-body">Early Access pricing for the first 30 days after launch. It's a thank-you to the people who show up early. After the Early Access window, Lifetime returns to its regular price. One-time purchase, Family Sharing enabled, unlimited future updates to FastShared Pro.</div>
    </details>
    <details class="faq-item">
      <summary>Is there a free trial?</summary>
      <div class="faq-body">No trial in v1 — the Free tier is the trial. It's generous enough (5 uploads/day, 100 MB, 24 h) to let you decide if the Pro limits actually matter to you before paying.</div>
    </details>
  </div>
</section>
```

**Step 2: Verify the FAQ uses the existing `.faq-item` + `.faq-body` styling** (already defined in global.css for the home page FAQ).

---

### Task C1.6: Add Schema.org Product markup for SEO

**Files:**
- Modify: `web/src/pages/pricing.astro` (inside `Base` props, via a nested `<script is:inline type="application/ld+json">`)

**Prerequisites:** C1.5 complete.

**Step 1: Add this script block at the very top of the `<main>` tag in `pricing.astro`.**

```astro
<script is:inline type="application/ld+json" set:html={JSON.stringify({
  '@context': 'https://schema.org',
  '@type': 'Product',
  name: 'FastShared Pro',
  description: 'Pro tier of FastShared — unlimited uploads, 30-day retention, iCloud sync, priority support. Available as Monthly, Annual, or one-time Lifetime.',
  brand: { '@type': 'Brand', name: 'FastShared' },
  offers: [
    { '@type': 'Offer', name: 'Pro Monthly',  price: '2.99',  priceCurrency: 'USD', availability: 'https://schema.org/InStock' },
    { '@type': 'Offer', name: 'Pro Annual',   price: '19.99', priceCurrency: 'USD', availability: 'https://schema.org/InStock' },
    { '@type': 'Offer', name: 'Pro Lifetime', price: '49.99', priceCurrency: 'USD', availability: 'https://schema.org/InStock' },
  ],
})} />
```

**Step 2: Verify.** Run `pnpm build` and grep the built HTML for `"Pro Lifetime"`.

**Expected:**
```
web/dist/pricing/index.html:..."Pro Lifetime","price":"49.99"...
```

**Step 3: Validate structured data** by pasting the page URL (after deploy) into https://validator.schema.org — should report 0 errors on the Product node.

---

### Task C1.7: Mobile responsiveness pass

**Files:**
- Modify: `web/src/pages/pricing.astro` if any adjustments needed.

**Prerequisites:** C1.4–C1.6 complete.

**Step 1: Run `pnpm dev` and open pricing page in browser.** Test at 375 px (iPhone SE), 768 px (iPad portrait), 1024 px (iPad landscape), 1440 px (laptop).

**Step 2: Confirm:**
- At 375 px: cards stack 1 column, ribbon doesn't overflow, FAQ is readable.
- At 768 px: cards go 2 columns, table scroll is not required.
- At 1024 px+: 4 columns, prices align across cards.
- Long feature labels don't wrap awkwardly.

**Step 3: If anything breaks, adjust the grid classes** (e.g., change `md:grid-cols-2` to keep one column longer).

**Expected output (screenshot taken in devtools):** 4 consistent card heights, no horizontal scroll at any breakpoint.

**If Task Fails:**
1. Cards different heights → add `h-full` to `article.tier-card` and `flex-1` to `.tier-features`
2. Ribbon clips → reduce `right: -32px` to `right: -28px`
3. Can't recover → `git restore web/src/pages/pricing.astro` and re-apply C1.3 from scratch

---

### Task C1.8: Code review checkpoint — Pricing page

**Prerequisites:** C1.1–C1.7 complete.

1. Dispatch all 3 reviewers in parallel:
   - REQUIRED SUB-SKILL: Use ring:requesting-code-review
   - ring:code-reviewer, ring:business-logic-reviewer, ring:security-reviewer on the diff touching `web/src/pages/pricing.astro` + `web/src/styles/global.css`

2. Handle findings by severity:
   - **Critical/High/Medium:** fix immediately, re-run reviewers until zero remain.
   - **Low:** add `TODO(review): [description] (reported by [reviewer] on 2026-04-19, severity: Low)` in the relevant file.
   - **Cosmetic:** add `FIXME(nitpick): [description] ...` in-line.

3. Proceed only when zero Critical/High/Medium issues remain.

---

## Part 2 — Landing page updates

### Task C2.1: Add "Pricing" link to Nav

**Files:**
- Modify: `web/src/components/Nav.astro`

**Prerequisites:** None. Can run in parallel with Part 1.

**Step 1: Replace the right-hand link block.**

Find this in `Nav.astro` (around lines 19–25):

```astro
  <a
    href="#testflight"
    class="font-mono text-[13px] tracking-wider uppercase text-milk/70 hover:text-amber transition-colors flex items-center gap-2"
    data-testid="nav-testflight"
  >
    TestFlight <span aria-hidden="true">→</span>
  </a>
```

Replace with:

```astro
  <div class="flex items-center gap-6">
    <a
      href="/pricing"
      class="font-mono text-[13px] tracking-wider uppercase text-milk/70 hover:text-amber transition-colors"
      data-testid="nav-pricing"
    >
      Pricing
    </a>
    <a
      href="#testflight"
      class="font-mono text-[13px] tracking-wider uppercase text-milk/70 hover:text-amber transition-colors flex items-center gap-2"
      data-testid="nav-testflight"
    >
      TestFlight <span aria-hidden="true">→</span>
    </a>
  </div>
```

**Step 2: Verify.** Open `/` and `/pricing` — both pages show Nav with "Pricing" link left of "TestFlight →".

---

### Task C2.2: Add "Start free" secondary CTA to Hero

**Files:**
- Modify: `web/src/components/Hero.astro` (around lines 26–35)

**Prerequisites:** None.

**Step 1: Find the CTA block.**

```astro
      <div class="mt-10 flex flex-wrap items-center gap-6">
        <a href="#testflight" class="btn-primary" data-testid="hero-cta">
          Join the TestFlight
          <span aria-hidden="true">→</span>
        </a>
        <a href="#how" class="btn-ghost">
          How it works
          <span aria-hidden="true">↓</span>
        </a>
      </div>
```

**Step 2: Replace with — add a third link, keep the primary unchanged.**

```astro
      <div class="mt-10 flex flex-wrap items-center gap-6">
        <a href="#testflight" class="btn-primary" data-testid="hero-cta">
          Join the TestFlight
          <span aria-hidden="true">→</span>
        </a>
        <a href="/pricing" class="btn-ghost" data-testid="hero-cta-pricing">
          Start free
          <span aria-hidden="true">→</span>
        </a>
        <a href="#how" class="btn-ghost">
          How it works
          <span aria-hidden="true">↓</span>
        </a>
      </div>
```

**Step 3: Verify.** Reload `/`. Three CTAs render side-by-side on desktop, wrap on mobile.

---

### Task C2.3: Add Pro tagline near Ephemeral Promise

**Files:**
- Modify: `web/src/components/EphemeralPromise.astro`

**Prerequisites:** None.

**Step 1: At the end of the `<ul>` block, add a fourth bullet OR add a single line below the list.** Prefer a separate sentence so it reads as an add-on, not a feature bullet.

Find the closing `</ul>` (line 28) and append below it, before the closing `</section>`:

```astro
  <p class="mt-10 font-mono text-[13px] tracking-[0.03em] text-milk/55 max-w-[720px]">
    <span class="text-amber">Pro</span> unlocks cross-device sync and 30-day links.
    <a href="/pricing" class="text-milk/70 hover:text-amber transition-colors underline-offset-4 underline decoration-milk/20">See pricing →</a>
  </p>
```

**Step 2: Verify.** Reload `/`. The sentence sits under the three mono bullets, linking to `/pricing`. Matches voice — "confident, not guilty-trip".

---

### Task C2.4: Verify sitemap includes /pricing

**Files:**
- Verify: `web/dist/sitemap-index.xml` + `web/dist/sitemap-0.xml`

**Prerequisites:** C1.1 complete (pricing page exists).

**Step 1: Build and inspect.**

```bash
cd web && pnpm build
cat dist/sitemap-0.xml
```

**Expected output:** `<loc>https://www.fastsha.red/pricing</loc>` appears in the output.

**Step 2: If missing, confirm `@astrojs/sitemap` is registered in `astro.config.mjs`** (it is — line 12). No code change needed; the integration auto-discovers pages in `src/pages/`.

**If the page is missing from sitemap:** Ensure `noindex: false` (the default), and the file is not under a dynamic-route folder.

---

### Task C2.5: Code review checkpoint — Landing updates

**Prerequisites:** C2.1–C2.4 complete.

1. REQUIRED SUB-SKILL: Use ring:requesting-code-review on the diff touching Nav, Hero, EphemeralPromise.
2. Severity handling as in C1.8.

---

## Part 3 — Privacy policy updates

### Task C3.1: Update privacy effective date

**Files:**
- Modify: `web/src/pages/privacy.astro` (line 20)

**Prerequisites:** None. Parallel-safe with all web and docs tasks.

**Step 1: Replace line 20.**

```astro
    <p class="font-mono text-[12px] tracking-[0.1em] uppercase text-amber mb-10">
      Effective 19 April 2026 · v1.1
    </p>
```

(Today's date, bump to v1.1 — keep the format used by the existing v1.0 entry.)

---

### Task C3.2: Add "Cross-device sync (Pro)" section to privacy

**Files:**
- Modify: `web/src/pages/privacy.astro`

**Prerequisites:** C3.1 complete.

**Step 1: Find the "Sub-processors" `<h2>` heading** (around line 147) and insert BEFORE it a new section.

```astro
      <h2 class="font-display font-semibold text-milk text-[26px] md:text-[30px] pt-6" style="letter-spacing: -0.02em;">
        Cross-device sync (Pro)
      </h2>
      <p>
        If you are a Pro subscriber, FastShared can sync your link-history
        metadata (token, filename, MIME type, timestamps, and link state —
        live, expired, revoked, or removed) across your Apple devices using
        Apple's <strong class="text-milk">CloudKit private database</strong>,
        scoped to your Apple ID's personal iCloud container. We never see this
        data — it lives in your own iCloud storage, covered by Apple's privacy
        terms, and we have no API to read or modify it.
      </p>
      <p>
        When you downgrade from Pro to Free, sync stops. The records already
        in your private iCloud container remain there for up to 30 days, after
        which iCloud prunes them naturally according to its own retention
        rules. If you want to remove them sooner, iOS Settings → Apple ID →
        iCloud → Manage Account Storage → FastShared → Delete from iCloud.
        Nothing about that flow touches our servers.
      </p>
      <p>
        This sync covers metadata only. The underlying file bytes always live
        on Cloudflare R2 with the lifecycle described above — they are never
        mirrored into iCloud.
      </p>
```

**Step 2: Verify at `/privacy`.** New section appears above "Sub-processors". Links and code formatting still render.

---

### Task C3.3: Add "Subscription data" section to privacy

**Files:**
- Modify: `web/src/pages/privacy.astro`

**Prerequisites:** C3.2 complete.

**Step 1: Find the "Your rights" `<h2>` heading** (around line 198) and insert BEFORE it a new section.

```astro
      <h2 class="font-display font-semibold text-milk text-[26px] md:text-[30px] pt-6" style="letter-spacing: -0.02em;">
        Subscription data (Pro)
      </h2>
      <p>
        When you purchase Pro, we store one server-side record that maps your
        device ID to Apple's transaction identifier, the tier you bought
        (monthly, annual, lifetime), its current status (active, expired,
        refunded), and its expiry timestamp. We use this to decide whether
        your device can upload under Pro limits.
      </p>
      <p>
        <strong class="text-milk">No billing information ever touches our
        servers.</strong> Apple handles the payment end-to-end: card, tax,
        receipt, refund. We only receive the transaction identifier from the
        App Store Server API, over a signed, authenticated channel. If you
        request a refund through Apple, Apple notifies us via server-to-server
        notifications and we revoke your Pro access within minutes.
      </p>
      <p>
        Subscription records are retained for as long as the associated
        device is registered, plus 90 days after cancellation, for audit and
        dispute resolution. After that, the record is pruned.
      </p>
```

**Step 2: Verify at `/privacy`.** New section appears between sub-processors and "Your rights".

---

### Task C3.4: Add "Delete a Pro subscription" bullet to "Your rights"

**Files:**
- Modify: `web/src/pages/privacy.astro`

**Prerequisites:** C3.3 complete.

**Step 1: In the "Your rights" `<ul>` block, append one more `<li>`** (after the existing "Complain" bullet, around line 243):

```astro
        <li class="flex gap-3 items-start">
          <span class="text-amber flex-none" aria-hidden="true">→</span>
          <span>
            <strong class="text-milk">Cancel or manage your Pro subscription</strong>
            at any time through iOS Settings → Apple ID → Subscriptions, or at
            <a href="https://apps.apple.com/account/subscriptions" class="text-amber hover:underline">apps.apple.com/account/subscriptions</a>.
            Apple processes the cancellation; we revoke Pro access when we
            receive Apple's server-to-server notification.
          </span>
        </li>
```

---

### Task C3.5: Code review checkpoint — Privacy

Same as C1.8 — dispatch 3 reviewers in parallel on the privacy diff.

---

## Part 4 — Terms of Service updates

### Task C4.1: Update terms effective date

**Files:**
- Modify: `web/src/pages/terms.astro` (line 20)

**Prerequisites:** None.

**Step 1: Update line 20.**

```astro
    <p class="font-mono text-[12px] tracking-[0.1em] uppercase text-amber mb-10">
      Effective 19 April 2026 · v1.1
    </p>
```

---

### Task C4.2: Add "Paid subscriptions — FastShared Pro" section

**Files:**
- Modify: `web/src/pages/terms.astro`

**Prerequisites:** C4.1 complete.

**Step 1: Find the `No permanent storage` `<h2>`** (around line 160) and INSERT BEFORE it the following block (covering billing, auto-renew, refunds, Family Sharing, tier caps, promotional pricing — all in one section for readability, with sub-headings).

```astro
      <h2 class="font-display font-semibold text-milk text-[26px] md:text-[30px] pt-6" style="letter-spacing: -0.02em;">
        Paid subscriptions — FastShared Pro
      </h2>
      <p>
        FastShared offers an optional Pro tier with three purchase options:
        <strong class="text-milk">Pro Monthly</strong> (auto-renewing, billed
        monthly), <strong class="text-milk">Pro Annual</strong> (auto-renewing,
        billed yearly), and <strong class="text-milk">Pro Lifetime</strong>
        (one-time, non-renewing). All purchases happen through Apple's in-app
        purchase system; Apple's payment and refund terms govern the
        transaction.
      </p>

      <h3 class="font-display font-semibold text-milk text-[20px] md:text-[22px] pt-4" style="letter-spacing: -0.015em;">Auto-renew disclosure</h3>
      <p>
        Pro Monthly and Pro Annual subscriptions renew automatically unless
        auto-renew is turned off at least 24 hours before the end of the
        current period. Your Apple ID is charged within 24 hours prior to the
        end of the current period for the next period. You can manage or
        cancel auto-renew at any time via iOS Settings → Apple ID →
        Subscriptions. Cancelling does not refund the current period; your
        Pro access remains until the end of the period you already paid for.
      </p>

      <h3 class="font-display font-semibold text-milk text-[20px] md:text-[22px] pt-4" style="letter-spacing: -0.015em;">Refunds</h3>
      <p>
        Refunds are handled entirely by Apple through
        <a href="https://apps.apple.com/support" class="text-amber hover:underline">apps.apple.com/support</a>
        or
        <a href="https://reportaproblem.apple.com" class="text-amber hover:underline">reportaproblem.apple.com</a>.
        We do not process refunds directly. If Apple grants a refund, Apple
        notifies us via server-to-server notifications and we revoke the Pro
        entitlement on the associated devices.
      </p>

      <h3 class="font-display font-semibold text-milk text-[20px] md:text-[22px] pt-4" style="letter-spacing: -0.015em;">Family Sharing</h3>
      <p>
        Pro Lifetime supports Apple Family Sharing — once the Family
        organiser enables it, up to six family members unlock Pro on their
        own Apple IDs. Pro Monthly and Pro Annual do not support Family
        Sharing in this version; each person needs their own active
        subscription.
      </p>

      <h3 class="font-display font-semibold text-milk text-[20px] md:text-[22px] pt-4" style="letter-spacing: -0.015em;">Tier caps</h3>
      <p>
        Each tier has limits — uploads per day, maximum file size, and
        maximum link retention. Current limits are published on the
        <a href="/pricing" class="text-amber hover:underline">pricing page</a>.
        We reserve the right to adjust these limits with at least 30 days
        notice, published on the pricing page and announced inside the app.
        Adjustments that are strictly to your benefit (higher caps, longer
        retention) may take effect without prior notice.
      </p>

      <h3 class="font-display font-semibold text-milk text-[20px] md:text-[22px] pt-4" style="letter-spacing: -0.015em;">Promotional pricing</h3>
      <p>
        The Pro Lifetime <strong class="text-milk">Early Access</strong>
        price is time-limited. After the Early Access window closes, Pro
        Lifetime is sold at its standard price, which will be displayed on
        the pricing page and in the App Store listing. Purchases completed
        during the Early Access window remain honoured at the Early Access
        price with no change to the included features.
      </p>
```

**Step 2: Verify at `/terms`.** New section renders with subheadings, correct typography, no layout breaks.

---

### Task C4.3: Code review checkpoint — Terms

Same as C1.8 on the terms diff.

---

## Part 5 — Marketing docs

### Task C5.1: Update `docs/marketing/app-store.md` — subtitle + promotional text [parallel]

**Files:**
- Modify: `docs/marketing/app-store.md`

**Prerequisites:** None.

**Intent:** Keep subtitle ≤ 30 chars, promotional text ≤ 170. Reshape subtitle to reference Pro. Add a Pro line to promotional text.

**Step 1: Propose two subtitle candidates** (add to the file under the existing "Subtitle" section as Option 4 + 5). The final pick stays as `Temporary share links, fast` unless the owner says otherwise.

```
**4. Pro-aware (candidate for launch week).**

Ephemeral share. Pro sync.
```
(24 / 30) — names Pro explicitly, keeps "ephemeral" as brand word. Loses the "fast" closer. Use only if the owner decides Pro messaging outranks speed.

```
**5. Pro-aware (alt).**

Temporary links. iCloud sync.
```
(28 / 30) — closer to existing voice, swaps "fast" for the Pro benefit.

**Step 2: Add a new "Promotional text — Pro launch variant" option under the existing promotional text section.**

```
**4. Pro launch variant.**

Share anything, get a temporary link, watch it vanish. No accounts, no residue. Pro unlocks unlimited uploads, 30-day links, and iCloud sync. Monthly, annual, or lifetime.
```
(169 / 170)

**Step 3: Verify by running `wc -c` on each proposed subtitle and promotional text.**

**Expected:** All are ≤ the stated limits.

---

### Task C5.2: Update `docs/marketing/app-store.md` — description (add Pro section)

**Files:**
- Modify: `docs/marketing/app-store.md`

**Prerequisites:** C5.1 complete.

**Step 1: In the existing description, insert a new section titled "FASTSHARED PRO" between "YOUR FILES, YOUR RULES" and "NOT INCLUDED — ON PURPOSE".** Keep existing bullets intact.

```
FASTSHARED PRO
• Unlimited uploads per day. No throttle. No counter.
• 2 GB per file — for the screen recording, the slide deck, the full-resolution export.
• Link retention up to 30 days — enough to ship a contract and still have the link alive next week.
• iCloud history sync. Your links follow you across iPhone, iPad, and Mac.
• Family Sharing on Lifetime — one purchase, up to six people.
• Priority support. Reply within one business day.
• Three ways to buy: $2.99/mo, $19.99/yr, or $49.99 once. Pick the one you don't have to think about.
```

**Step 2: Re-measure the full description length.** Current count is 2777/4000. The new section is ~650 chars. Expected total: ~3427/4000. Verify:

```bash
# from repo root
awk '/^```$/{p=!p; next} p' docs/marketing/app-store.md | head -n 200 | wc -c
```

**Expected:** Character count well below 4000.

---

### Task C5.3: Update `docs/marketing/app-store.md` — keywords + What's New

**Files:**
- Modify: `docs/marketing/app-store.md`

**Prerequisites:** C5.2 complete.

**Step 1: Replace the existing keywords block with a Pro-aware pack.**

```
share,link,temporary,ephemeral,upload,transfer,file,expire,private,airdrop,sync,subscription,pro,icloud
```
(100 / 100 — exactly at limit)

Cuts: `vanish`, `cloud`, `send`, `clip` — re-evaluate in Pack B/C/D if data shows conversion loss.
Adds: `sync`, `subscription`, `pro`, `icloud`.

**Step 2: Add a new "What's New in Version 1.1.0" block** (for the Pro launch; v1.0 entry stays as-is).

```
## What's New in Version 1.1.0

FastShared Pro is here. Unlimited uploads, 30-day links, iCloud history sync across iPhone, iPad, and Mac. Pick Monthly at $2.99, Annual at $19.99 — or grab Lifetime at $49.99 during Early Access with Family Sharing included. Free stays free, no strings. Every link is still temporary by design.
```

(334 / 4000)

**Step 3: Verify char counts.** Keywords MUST be ≤ 100. Pro-aware keyword pack is at exactly 100 — count it:

```bash
printf 'share,link,temporary,ephemeral,upload,transfer,file,expire,private,airdrop,sync,subscription,pro,icloud' | wc -c
# Expected: 100
```

---

### Task C5.4: Update `docs/marketing/aso-keywords.md`

**Files:**
- Modify: `docs/marketing/aso-keywords.md`

**Prerequisites:** C5.3 complete.

**Step 1: Add a new primary pack** (replacing or paralleling the existing one — keep both so the team sees the shift).

**Section to add** (after the existing "Keyword field — primary pack" section):

```
### Pro-launch pack (committed for v1.1)

```
share,link,temporary,ephemeral,upload,transfer,file,expire,private,airdrop,sync,subscription,pro,icloud
```

(100 / 100)

#### Per-keyword delta vs v1.0 pack

| keyword        | change   | rationale                                                              |
| -------------- | -------- | ---------------------------------------------------------------------- |
| `sync`         | added    | Pro iCloud sync is the core differentiator; also catches "photo sync". |
| `subscription` | added    | High-intent for people comparing subscription utilities.               |
| `pro`          | added    | Owns the in-app-purchase search funnel.                                |
| `icloud`       | added    | Apple-native match; pairs with `airdrop` for the ecosystem query.      |
| `vanish`       | removed  | Brand voice word; low volume, freed slot for Pro intent.               |
| `cloud`        | removed  | `icloud` is more specific and higher-intent for our audience.          |
| `send`         | removed  | `share` + `upload` + `transfer` already cover the intent space.        |
| `clip`         | removed  | Niche; Pro pack needs slots more than clipboard adjacency does.        |

#### Measurement
Hold for 7 days post v1.1 release before iterating. Compare installs-per-impression vs v1.0 pack (which stays as the fallback if Pro pack underperforms on conversion).
```

---

### Task C5.5: Update `docs/marketing/taglines.md` (optional Pro-aware alternates)

**Files:**
- Modify: `docs/marketing/taglines.md`

**Prerequisites:** None.

**Step 1: Add a new section "Pro-aware taglines (v1.1)"** after the existing "Tagline — 5 options, ranked" block.

```
---

## Pro-aware taglines (v1.1)

The primary tagline ("Share anything. Get a link. Watch it vanish.") stays
as the hero headline. These alternates are for the pricing page sub-header,
paid ad rotations, or Pro-specific surfaces where the tier actually matters.

**A. For the pricing page sub-head.**

```
One gesture. One link. Your call on the rest.
```
(47 / 60) — already in use on /pricing. Nods at Pro without naming it.

**B. For the Pro paywall inside the app.**

```
Unlimited uploads. 30-day links. iCloud sync.
```
(46 / 60) — literal, feature-forward. Works because it stays factual, no
"unlock the power" residue.

**C. For the Lifetime Early Access banner.**

```
Buy once. Share forever-ish.
```
(28 / 60) — the hyphen-ish acknowledges that nothing is literally forever,
which keeps the voice honest. "Ephemeral by design" still applies inside
the app — Lifetime buys you the tool, not file permanence.
```

---

### Task C5.6: Update `docs/marketing/voice-tone.md` with Pro/paywall guidance

**Files:**
- Modify: `docs/marketing/voice-tone.md`

**Prerequisites:** None.

**Step 1: Append this section before the final "Brand-speak cheat sheet" section.**

```
---

## Pro / paywall tone

Pro messaging is **confident, transparent, and never guilty-trip**. The
paywall is the product helping you decide, not the product talking you
into a purchase.

### Do

1. **"Unlimited uploads. 30-day links. iCloud sync."** — facts first. The
   reader picks.
2. **"Free stays free."** — whenever Pro is introduced, reassure that Free
   isn't getting worse. It's a load-bearing sentence.
3. **"Pick the one you don't have to think about."** — honest hint that
   Annual is usually the right pick without hectoring the reader.

### Don't

1. **"Upgrade to unlock the full power of FastShared."** — "unlock the
   power" is the marketing residue we always cut.
2. **"Don't miss out on Early Access!"** — FOMO with exclamation mark.
   Both banned.
3. **"Limited time offer — act now!"** — banned for the same reason.
   Early Access is time-bounded, state the end date instead:
   "Early Access price through [date]."
4. **"Try Pro free for 7 days."** — there is no trial in v1. Don't promise
   what the product doesn't ship.

### Word list — Pro-specific

| prefer                             | avoid                                                      |
| ---------------------------------- | ---------------------------------------------------------- |
| Pro (capital P)                    | pro (lowercase), PRO (shouting)                            |
| Pro Monthly / Pro Annual / Lifetime | monthly plan / yearly plan / lifetime plan (wordier, no gain) |
| unlimited uploads                  | "no limits!"                                               |
| subscription                       | "paid tier", "premium" (Apple prefers `subscription`)      |
| auto-renew                         | "automatically continues" (Apple legal language wants `auto-renew`) |
| priority support                   | "VIP support" (sounds cheap)                               |
| Early Access (Title Case)          | "early bird", "launch special" (cringe)                    |
| Family Sharing                     | "family plan" (Apple calls it Family Sharing)              |
```

---

### Task C5.7: Code review checkpoint — Marketing docs

Same as C1.8 on the marketing diff (app-store.md, aso-keywords.md, taglines.md, voice-tone.md).

---

## Part 6 — Product overview

### Task C6.1: Add "Tiers" section to `docs/product/overview.md`

**Files:**
- Modify: `docs/product/overview.md`

**Prerequisites:** None.

**Step 1: Append this section after the "MVP scope" section and before "Non-goals (MVP)".**

```
## Tiers (v1.1 Pro launch)

FastShared ships in two tiers:

### Free — acquisition + casual users
- 5 uploads per day.
- 100 MB max file size.
- Up to 24 h retention ceiling.
- Single-device history (SwiftData, local to the device).
- No cross-device sync.
- All the core ephemerality guarantees (private bucket, signed reads,
  no-residue). Free is not a crippled demo — it is a real product for
  people who share occasionally.

### Pro — power users, consultants, Apple ecosystem loyalists
- Unlimited uploads per day.
- 2 GB max file size (per single-PUT upload in v1; multipart is post-MVP).
- Up to 30 day retention ceiling.
- Cross-device history sync via iCloud (CloudKit private database).
- Priority support, one-business-day SLA.
- Family Sharing on Lifetime (up to 6 members).

### Why Opt B — iCloud metadata sync, not BYO storage

The decision, already captured in session memory: Pro syncs **metadata
only** through CloudKit's private database — never the file bytes. Files
always live on our R2 bucket with the same ephemeral lifecycle as Free.

Why not Opt A (BYO storage — let Pro users point at their own iCloud /
Dropbox): breaks the ephemerality contract, fragments the abuse model,
blows up the engineering surface. The core value of FastShared is "every
link expires and the file is deleted on schedule"; we can't guarantee that
if the file isn't in our bucket.

Opt B gives the cross-device benefit (history follows you from iPhone to
Mac) without changing where the bytes live. Apple is the sub-processor for
the metadata. We never see it.

### Pricing rationale

- **$2.99 / month.** Impulse-buy ceiling. Under $3 is the threshold for
  "yes, why not" among Apple-ecosystem subscribers; above that, churn
  climbs hard.
- **$19.99 / year.** Equivalent monthly price of $1.67 — a ~44% discount
  vs monthly. Enough to convert the "I'll probably keep using this"
  crowd into an annual commit, which drops support volume and boosts
  retention metrics.
- **$49.99 / Lifetime (Early Access).** PR beat — "pay once for a
  privacy tool" is still rare enough in 2026 to get a headline. Also a
  risk hedge: if the product survives, the average lifetime revenue per
  Lifetime buyer exceeds Annual after ~2.5 years; if it doesn't, we got
  the cash up-front. Family Sharing on Lifetime turns one sale into six
  activations and amplifies word of mouth without re-billing.

No introductory offers. No free trial. The Free tier is the trial — and
it's generous enough to be honest about it.
```

**Step 2: Verify.** Open the file; new section sits between MVP scope and Non-goals, formatting consistent with the rest of the doc.

---

### Task C6.2: Code review — product overview

Lightweight — dispatch ring:business-logic-reviewer only (no code to review; business reviewer catches inconsistency with pricing docs).

---

## Part 7 — App Store Connect manual runbook

This is a RUNBOOK, not code. Follow step-by-step in the App Store Connect web UI. Each step ends in an acceptance signal (screenshot or sandbox test). Do NOT skip acceptance.

**Pre-flight (before Task C7.1):**

- [ ] Paid Apps Agreement is active in App Store Connect → Agreements, Tax, and Banking.
- [ ] Tax forms filled out and signed.
- [ ] Banking details saved.
- [ ] Your ASC role is **Admin** or **App Manager** for FastShared.

If any of these is missing, STOP — the rest of Part 7 will not be possible.

---

### Task C7.1: Create Subscription Group "FastShared Pro"

**ASC screen:** App Store Connect → My Apps → FastShared → Monetization → Subscriptions → `+` (Create Subscription Group).

**Steps:**
1. Reference Name: `FastShared Pro`
2. Save.
3. In the new group, add localisations:
   - English (U.S.): Display Name `FastShared Pro`, App Name `FastShared`.
4. Save.

**Acceptance:** Subscription group appears in the list with `FastShared Pro` as its name. Screenshot saved to `/tmp/asc-C7.1.png`.

---

### Task C7.2: Create IAP product `.pro.monthly`

**ASC screen:** Subscription group "FastShared Pro" → `+ Add` → Auto-Renewable Subscription.

**Steps:**
1. Reference Name: `Pro Monthly`.
2. Product ID: `red.fastsha.fastshared.pro.monthly`
   (Use the exact bundle-prefix Plan A and Plan B expect. The reverse-DNS prefix must match what the Apple client uses when calling `Product.products(for:)`.)
3. Subscription Duration: **1 Month**.
4. Subscription group: already set to `FastShared Pro`.
5. Price: USD **$2.99**. Click "Apply to All Territories" → Auto-managed pricing ON.
6. Localisations (English):
   - Display Name: `FastShared Pro Monthly`
   - Description: `Unlimited uploads, 2 GB files, 30-day links, iCloud history sync.`
7. Review Screenshot: 1242×2688 pixel IAP screenshot (iPhone 6.9"). Upload placeholder for now; final screenshot created in C7.8.
8. Review Notes: `Pro Monthly unlocks unlimited uploads per day, 2 GB max file size, 30-day link retention, and cross-device history sync via iCloud CloudKit private database.`
9. Family Sharing: **OFF** (confirm with owner first, per global prerequisite checklist).
10. Save.

**Acceptance:** Product status is "Missing Metadata" or "Ready to Submit". Screenshot saved.

---

### Task C7.3: Create IAP product `.pro.annual`

**ASC screen:** Subscription group "FastShared Pro" → `+ Add` → Auto-Renewable Subscription.

**Steps:**
1. Reference Name: `Pro Annual`.
2. Product ID: `red.fastsha.fastshared.pro.annual`
3. Subscription Duration: **1 Year**.
4. Price: USD **$19.99**. Auto-managed pricing ON. All territories.
5. Localisations (English):
   - Display Name: `FastShared Pro Annual`
   - Description: `Unlimited uploads, 2 GB files, 30-day links, iCloud sync. Save about 45% vs monthly.`
6. Review Screenshot: 1242×2688 — placeholder then final in C7.8.
7. Review Notes: `Pro Annual unlocks unlimited uploads per day, 2 GB max file size, 30-day link retention, iCloud cross-device sync, priority support. Billed once per year.`
8. Family Sharing: **OFF**.
9. Save.

**Acceptance:** Product appears in subscription group next to Monthly. Screenshot saved.

---

### Task C7.4: Create IAP product `.pro.lifetime` (Non-Consumable)

**ASC screen:** App Store Connect → My Apps → FastShared → Monetization → In-App Purchases → `+` (New) → **Non-Consumable** (NOT a subscription).

**Steps:**
1. Reference Name: `Pro Lifetime`.
2. Product ID: `red.fastsha.fastshared.pro.lifetime`
3. Price: USD **$49.99** (Early Access pricing). Auto-managed pricing ON. All territories.
4. Localisations (English):
   - Display Name: `FastShared Pro Lifetime`
   - Description: `Buy Pro once. Unlimited uploads, 2 GB files, 30-day links, iCloud sync, Family Sharing included.`
5. Review Screenshot: 1242×2688 — placeholder then final in C7.8.
6. Review Notes: `Pro Lifetime is a one-time purchase unlocking all Pro features forever (unlimited uploads, 2 GB files, 30-day retention, iCloud sync, priority support). Family Sharing supports up to 6 family members.`
7. Family Sharing: **ON** (confirm with owner — per global prerequisite checklist).
8. Save.

**Acceptance:** Lifetime product appears under In-App Purchases (separate from subscription group). Screenshot saved.

---

### Task C7.5: Configure Server-to-Server Notifications v2

**ASC screen:** My Apps → FastShared → App Information → scroll to **App Store Server Notifications**.

**Steps:**
1. Notification Version: **Version 2**.
2. Production Server URL: `https://fastsha.red/v1/iap/webhook`
3. Production Server URL Version: 2
4. Sandbox Server URL: `https://fastsha.red/v1/iap/webhook` (same — the webhook handler in Plan A differentiates sandbox vs production by the notification payload's `environment` field).
5. Sandbox Server URL Version: 2
6. Save.

**Acceptance:** Both URLs are saved. Run the "Send Test Notification" button (if available); Plan A's webhook should log the receipt. If Plan A is not yet deployed, log the URL and defer the test to Plan A's completion.

**If Task Fails:**
- URL rejected as invalid: the webhook must return 200 OK on a test POST. Wait for Plan A to deploy the `/v1/iap/webhook` route, then retry.
- Don't: configure a different URL. The webhook URL is contract-locked to Plan A.

---

### Task C7.6: Generate App Store Connect API key for StoreKit Server API

**ASC screen:** App Store Connect → Users and Access → Integrations → **App Store Connect API** → Keys → `+` (Generate API Key).

**Steps:**
1. Name: `fastshared-iap-server-v1`
2. Access: **App Manager** (minimum role needed to query purchases; DO NOT give Admin).
3. Click **Generate**.
4. Download the `.p8` file ONCE — Apple does not let you download it again. Store it in the password manager immediately.
5. Copy the **Key ID** (format: 10 chars, e.g., `A1B2C3D4E5`). Save it.
6. Copy the **Issuer ID** (UUID at the top of the Keys page). Save it.

**Acceptance:** `.p8` saved to password manager; Key ID + Issuer ID written down.

---

### Task C7.7: Store the .p8 + IDs as Wrangler secrets

**ASC screen:** N/A — local terminal.

**Prerequisites:** C7.6 complete. Plan A's Worker project exists at `backend/` (confirm with Plan A).

**Steps:**

1. Base64-encode the .p8 file (Cloudflare Workers cannot handle multi-line secrets directly):

```bash
cd /Users/matheuskindrazki/development/crazy-ideas/fastshared/backend
base64 -i /path/to/AuthKey_A1B2C3D4E5.p8 -o /tmp/p8.b64
```

2. Store as Wrangler secrets for both production and staging:

```bash
# Production
wrangler secret put APP_STORE_CONNECT_KEY_ID --env production
# Paste: A1B2C3D4E5

wrangler secret put APP_STORE_CONNECT_ISSUER_ID --env production
# Paste: 57246542-96fe-1a63-e053-0824d011072a (replace with real UUID)

wrangler secret put APP_STORE_CONNECT_KEY_P8_B64 --env production < /tmp/p8.b64

# Repeat for staging env if applicable
wrangler secret put APP_STORE_CONNECT_KEY_ID --env staging
wrangler secret put APP_STORE_CONNECT_ISSUER_ID --env staging
wrangler secret put APP_STORE_CONNECT_KEY_P8_B64 --env staging < /tmp/p8.b64
```

3. Verify secrets exist:

```bash
wrangler secret list --env production
# Expected: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_P8_B64 present
```

4. Shred the local copy of `/tmp/p8.b64`:

```bash
shred -u /tmp/p8.b64 2>/dev/null || rm -P /tmp/p8.b64
```

**Acceptance:** `wrangler secret list` shows the three keys; local temp copy deleted.

**If Task Fails:**
- `wrangler: command not found` → `pnpm install -g wrangler` (or run `pnpm dlx wrangler …`).
- Secret rejected (too large): the base64 of a p8 is ~340 bytes — well within the 1024-byte secret cap. If rejected, re-check the base64 is single-line (`base64 -i file.p8 | tr -d '\n'`).

---

### Task C7.8: IAP screenshots + review copy finalisation

**ASC screen:** Each IAP's detail page → Review Information → upload screenshot.

**Steps:**
1. Each of the 3 IAPs needs one 1242×2688 screenshot showing the paywall inside the app (from Plan B).
2. File naming: `iap-monthly-6.9.png`, `iap-annual-6.9.png`, `iap-lifetime-6.9.png`.
3. Source: Apple client Plan B produces the paywall UI; screenshot it on Simulator (iPhone 16 Pro Max = 6.9" = 1242×2688).
4. Upload one screenshot per IAP.
5. Re-review localised Display Name + Description (already filled in C7.2 / C7.3 / C7.4 — verify accuracy).
6. Save each IAP.

**Acceptance:** Every IAP status transitions from "Missing Metadata" to "Ready to Submit" or equivalent. Each has a screenshot. Screenshot saved of the IAP list.

**If Task Fails:**
- Screenshot rejected (wrong size): iPhone 6.9" spec is 1290×2796 in iOS 18 devices. Use 1242×2688 for iPhone 14 Pro Max (legacy 6.7") if 6.9" is the issue. Confirm current Apple spec on https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/.

---

### Task C7.9: Configure Tax Category and App Privacy (subscription data)

**ASC screen:** My Apps → FastShared → App Information → Tax Category.

**Steps:**
1. Tax Category: **Software Utility** (confirm with accountant; this affects how Apple withholds tax). Save.
2. Go to App Privacy: My Apps → FastShared → App Privacy.
3. Data Types → Add: **Purchases** → Purchase History.
4. Linked to User: **NO** (we don't link purchases to a named user — only to the device ID).
5. Used for Tracking: **NO** (ATT not required because we don't track).
6. Used for: **App Functionality** (gating Pro features).
7. Save.

**Acceptance:** App Privacy shows "Purchases" as the only new data type added. ATT confirmation remains "Not Required".

**Note:** Existing privacy declarations (file uploads, request logs) stay as-is — do NOT remove them.

---

### Task C7.10: Create App Review sandbox tester account

**ASC screen:** Users and Access → Sandbox → Testers → `+`.

**Steps:**
1. Create a sandbox tester:
   - First/Last: `FastShared Review`
   - Email: `sandbox-review+v1@fastsha.red` (or use `+` aliasing on your domain)
   - Password: strong, stored in password manager.
   - App Store Territory: United States.
2. Save.
3. Share credentials with Apple App Review via the submission's Review Information → Sign-In Info → Demo Account (only if Apple asks; FastShared doesn't require sign-in, so typically N/A, but Pro reviewers may need a sandbox Apple ID to test purchases).

**Acceptance:** Sandbox tester appears in the list. Credentials stored.

---

### Task C7.11: ASC runbook — final pre-submission check

**Steps (read only, verify):**
- [ ] 3 IAPs created with exact Product IDs: `red.fastsha.fastshared.pro.monthly`, `.pro.annual`, `.pro.lifetime`.
- [ ] Subscription group `FastShared Pro` contains Monthly + Annual.
- [ ] Lifetime is a Non-Consumable IAP outside the subscription group.
- [ ] Prices: $2.99 / $19.99 / $49.99 USD, auto-managed on.
- [ ] Family Sharing: OFF on Monthly + Annual, ON on Lifetime.
- [ ] S2S notification URL set for both Production and Sandbox.
- [ ] ASC API key generated, .p8 + Key ID + Issuer ID stored as Wrangler secrets.
- [ ] IAP screenshots uploaded.
- [ ] Tax category set. App Privacy declares Purchases.
- [ ] Sandbox tester created.

**Acceptance:** Every row ticked. Proceed to launch sequencing (Part 8).

---

## Part 8 — Launch sequencing

### Task C8.1: Define the launch-week ordered checklist

**Files:**
- Create: `docs/marketing/launch-sequence-pro.md`

**Prerequisites:** All prior tasks in Plan C complete; Plan A and Plan B also at their respective GA gates.

**Step 1: Create the file.**

```markdown
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
- Verify https://www.fastsha.red/pricing is live, sitemap includes it,
  schema.org Product markup validates clean.
- Update App Store metadata per `docs/marketing/app-store.md`:
  - Subtitle (if switching to Pro-aware variant)
  - Promotional text: v4 Pro-launch variant
  - Description: v1.1 with Pro section
  - Keywords: v1.1 Pro pack (7-day hold from this point before next rotation)
  - What's New in Version 1.1.0

## Week 5 — App Store Review submission

- Submit v1.1 binary with Pro IAPs attached.
- Review notes: "Pro unlocks unlimited uploads, 30-day retention, and
  cross-device history sync via iCloud private database. Free tier
  unchanged."
- Sandbox test account: `sandbox-review+v1@fastsha.red`.
- Expect 24–72 h review. Respond to any reviewer questions same-day.

## Week 6 — Launch day

- Morning (Pacific, 00:01 PT): release v1.1 via "Release this version
  manually" → Release.
- Product Hunt post at 00:01 Pacific — reuse `docs/marketing/launch-producthunt.md`
  with an added line about Pro + Early Access.
- Hacker News "Show HN" at ~09:00 Eastern — reuse `docs/marketing/launch-hn.md`,
  lead with "FastShared Pro is out; free tier unchanged; here's what
  Pro adds."
- Twitter thread at ~10:00 Eastern — reuse `docs/marketing/launch-thread-twitter.md`
  with a final tweet about Early Access Lifetime + a countdown to the
  closing date.
- Monitor: App Store Connect Analytics, Cloudflare Workers logs,
  subscription webhook activity. Any P1 regression → rollback binary
  (ASC "Remove from sale") and patch.

## Post-launch (D+7, D+14, D+30)

- ASO measurement per `docs/marketing/aso-keywords.md` (Pack B/C/D
  rotation if Pro pack underperforms).
- Churn signal review on Monthly (Apple reports first-month retention
  at D+30).
- Early Access Lifetime window closes at D+30 → flip price to standard,
  update pricing page + app-store.md + internal dashboards.
```

**Step 2: Verify.** File exists; cross-refs to existing marketing docs resolve.

---

### Task C8.2: Code review checkpoint — Launch sequencing + final

1. REQUIRED SUB-SKILL: Use ring:requesting-code-review on the full diff of Plan C (all files touched).
2. Severity handling as in C1.8. At this final checkpoint, all 3 reviewers MUST find zero Critical/High/Medium issues.
3. Merge branch to `main` only after sign-off.

---

## Failure Recovery — Global

**If anything fails mid-plan:**

1. **Web build fails:** `cd web && rm -rf .astro dist node_modules && pnpm install && pnpm build`. If still broken, `git restore web/` and re-apply the latest task.
2. **Wrong content in privacy/terms:** `git restore web/src/pages/privacy.astro web/src/pages/terms.astro` and re-apply C3.x / C4.x.
3. **ASC misconfiguration:** most ASC fields are editable without resubmission, EXCEPT Product ID (permanent). If a Product ID is wrong, the product must be marked "Removed from sale" and recreated with the correct ID — this is costly and blocks Plan B.
4. **Wrangler secret leak:** rotate the ASC API key via Users and Access → Integrations → Revoke, then generate a new one and re-run C7.6 + C7.7. Audit backend logs for any use of the leaked key.
5. **Cannot recover:** stop, document what failed and why, return to the human partner. Do NOT improvise on legal copy, ASC configuration, or pricing.

---

## Plan completeness checklist

- [x] Header with goal, architecture, tech stack, prerequisites
- [x] Verification commands with expected output
- [x] Tasks broken into bite-sized steps (2-5 min each on code tasks; ASC tasks slightly longer because of UI navigation, capped at ~10 min each with explicit acceptance)
- [x] Exact file paths for all web/doc files
- [x] Complete code (no placeholders) for all Astro/CSS
- [x] Exact ASC screens with fill-in values
- [x] Expected output for every verification command
- [x] Failure recovery per task + global
- [x] Code review checkpoints: C1.8, C2.5, C3.5, C4.3, C5.7, C6.2, C8.2 — one per part
- [x] Severity-based issue handling documented
- [x] Zero-Context Test: a skilled dev with only this plan can ship every part
- [x] Character-count budgets respected (subtitle ≤ 30, promo ≤ 170, keywords ≤ 100, description ≤ 4000)
- [x] Scope enforced: nothing from Plan A (backend) or Plan B (Apple) is touched
