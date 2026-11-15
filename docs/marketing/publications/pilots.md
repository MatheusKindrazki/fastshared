# FastShared — Pilot Program Strategy & Validation Plan

A structured roadmap for onboarding, interviewing, and evaluating the initial ten pilot users before building web billing.

---

## 1. Profile of the 10 pilots

To validate the thesis across varied client delivery workflows, we recruit ten independent consultants and solo freelancers who send deliverables (HTML, PDF, or ZIP bundles) to paying clients on a weekly or bi-weekly cadence.

### Pilot archetypes
1. **Pilot 1 — Independent Data Consultant:** Delivers interactive BI dashboards and analysis compiled from Plotly or Observable. Sends weekly updates to corporate stakeholders.
2. **Pilot 2 — Freelance UX / UI Designer:** Prototypes user flows using Claude Artifacts and v0, exporting standalone HTML/CSS components for client design reviews.
3. **Pilot 3 — Full-stack Web Contractor:** Ships proof-of-concept landing pages and compiled Vite/Tailwind demo builds as client deliverables before deploying to production.
4. **Pilot 4 — Technical SEO & Web Performance Auditor:** Generates comprehensive single-page HTML audit reports (Lighthouse/Crux exports) for marketing agencies.
5. **Pilot 5 — Financial Modeler / Fractional CFO:** Sends interactive ROI calculators and financial scenario models built in HTML/JavaScript to executive clients.
6. **Pilot 6 — QA / Test Automation Engineer:** Shares interactive Playwright and Cypress HTML test run execution reports with engineering clients.
7. **Pilot 7 — Boutique Marketing Strategist:** Delivers digital proposals, pitch presentations, and campaign decks as high-resolution PDFs and interactive landing pages.
8. **Pilot 8 — Cybersecurity & Compliance Assessor:** Delivers executive vulnerability summaries and audit roadmaps as secure, temporary links to enterprise clients.
9. **Pilot 9 — Conversion Rate Optimization (CRO) Specialist:** Shares interactive A/B test result summaries and visual heatmaps with e-commerce clients.
10. **Pilot 10 — AI Workflow & Automation Consultant:** Delivers custom AI workflow diagrams and interactive client demo bots using Claude and Cursor.

---

## 2. Where to find them without scraping personal data

Outreach must remain ethical, manual, and respectful. We do not scrape directories, harvest private emails, or purchase lead lists. 

Instead, we identify candidates through organic public participation:

### A. Public community discussions
- **Specialized Slack and Discord communities:** Participate in open channels like `#freelance-help`, `#showcase`, and `#tools` in communities such as dbt Community, Locally Optimistic (data consultants), Designer Hangout, and MicroConf Connect.
- **Approach:** Respond to members discussing client handoff friction, asking if they would like to test an early utility designed specifically for interactive deliverables.

### B. Public intent listening on social platforms
- **Search terms on Twitter/X and Bluesky:** Search for public posts containing:
  - `"waiting on client feedback"`
  - `"client ghosting proposal"`
  - `"share Claude artifact client"`
  - `"DocSend alternative"`
- **Approach:** Send a direct, personalized reply or DM (using the templates in `launch-kit.md`) acknowledging their specific situation.

### C. Developer forums and tool question threads
- **GitHub Discussions & community forums:** Monitor threads in repositories like Evidence.dev, Quarto, and Plotly where users ask: *"How do I share this report with a client without setting up a server?"*
- **Approach:** Offer a practical answer explaining the options, mentioning FastShared as an available tool for instant publishing.

### D. Founder network and warm introductions
- Reach out to former colleagues, agency owners, and freelance peers within the founder's immediate network, asking for introductions to consultants actively pitching new clients this month.

---

## 3. Interview scripts

Each pilot participates in two structured conversations: an onboarding interview before sending their first link, and a review interview after two weeks of real client use.

### Interview 1: Onboarding & Baseline Workflow (15 minutes)

#### Objective
Understand the pilot's current client delivery habits, friction points, and existing baseline for client feedback.

#### Questions:
1. **Current delivery workflow:**  
   *"Walk me through the last time you sent a deliverable or proposal to a client. What file format was it, and how did you deliver it?"*
2. **The waiting window:**  
   *"What happened between clicking 'send' and receiving their reply? How did you know whether they had opened or reviewed it?"*
3. **Format hurdles:**  
   *"Have you ever had a client struggle to open an interactive HTML report, prototype, or download an archive? How did you resolve that?"*
4. **Current tracking tools:**  
   *"Do you currently use any tool (like DocSend, Mailchimp, or URL shorteners) to track client opens? What do you dislike about that setup?"*
5. **Live onboarding:**  
   *"Let's take a sample deliverable or proposal you are planning to send this week. Let's drag it into FastShared and set up the link right now."*

---

### Interview 2: Retrospective & Willingness to Pay (20 minutes)

#### Objective
Evaluate real-world usage, notification accuracy, behavioral changes in follow-up timing, and willingness to pay US$15/month.

#### Questions:
1. **Actual usage volume:**  
   *"How many client deliverables or proposals did you publish through FastShared over the past two weeks?"*
2. **Notification experience:**  
   *"Tell me about the first time your iPhone pinged with 'Opened in a browser'. Where were you, and what was your immediate reaction?"*
3. **Signal accuracy:**  
   *"Did you notice any false alarms—for instance, an alert firing when you pasted the link into Slack or WhatsApp before the client opened it?"*
4. **Impact on client follow-up:**  
   *"Did knowing when the page was opened change how or when you followed up with the client? Did it change your confidence during the engagement?"*
5. **Friction and rough edges:**  
   *"What felt clunky, confusing, or missing during the publishing or viewing experience?"*
6. **Willingness to pay (Kill Gate Evaluation):**  
   *"When your 3-month pilot ends, FastShared Pro will be US$15 per month (or US$144 annually). Would you pay that to keep using it for your client sends, or would you switch back to your previous setup? What specifically makes it worth (or not worth) US$15/month to you?"*

---

## 4. Minimum spreadsheet to measure kill gates

To decide whether to proceed with building billing (Week 8 gate), track each pilot's activity in a minimal tabular ledger.

### Evaluation criteria (from mrr-plan.md):
- **Gate 1 (Repeat Usage):** At least 6 of the 10 pilots must publish more than once for real client sends.
- **Gate 2 (Willingness to Pay):** At least 2 of the 10 pilots must affirm they would pay US$15/month.

### Spreadsheet template

| Pilot ID | Name / Handle | Specialization | Onboard Date | Deliverable Type | Week 1 Sends | Week 2 Sends | Total Sends | False Positives? | Follow-up Value (1-5) | Would Pay US$15/mo? | Key Qualitative Feedback | Gate 1 Pass? (>1 send) | Gate 2 Pass? (Pay $15) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **P-01** | Pilot A | Data Consultant | YYYY-MM-DD | Plotly HTML | 2 | 1 | 3 | No | 5 | Yes | "Knowing they looked at the report before our call was huge." | PASS | PASS |
| **P-02** | Pilot B | UX Designer | YYYY-MM-DD | Claude Artifact | 1 | 2 | 3 | No | 4 | Yes | "Much cleaner than sending Claude conversation links." | PASS | PASS |
| **P-03** | Pilot C | Web Contractor | YYYY-MM-DD | Vite ZIP | 1 | 0 | 1 | No | 3 | Maybe | "Liked it, but most clients just want the git repo." | FAIL | FAIL |
| **P-04** | Pilot D | SEO Auditor | YYYY-MM-DD | HTML Audit | 3 | 2 | 5 | No | 5 | Yes | "Saves me from configuring S3 buckets for every audit." | PASS | PASS |
| **P-05** | Pilot E | Fractional CFO | YYYY-MM-DD | HTML Model | 1 | 1 | 2 | No | 4 | Maybe | "Needs password protection before I send financial PII." | PASS | FAIL |
| **P-06** | Pilot F | QA Engineer | YYYY-MM-DD | Playwright HTML | 2 | 3 | 5 | No | 4 | Yes | "Instant hosting for test reports without CI overhead." | PASS | PASS |
| **P-07** | Pilot G | Marketing Strategist| YYYY-MM-DD | PDF Pitch Deck | 1 | 1 | 2 | No | 3 | No | "DocSend's page-by-page time tracking is still needed for decks."| PASS | FAIL |
| **P-08** | Pilot H | Security Assessor | YYYY-MM-DD | HTML Summary | 1 | 0 | 1 | No | 2 | No | "Requires password protection and NDA gating." | FAIL | FAIL |
| **P-09** | Pilot I | CRO Consultant | YYYY-MM-DD | HTML Dashboard | 2 | 2 | 4 | No | 5 | Yes | "Immediate alerts allow me to time follow-up emails perfectly." | PASS | PASS |
| **P-10** | Pilot J | AI Consultant | YYYY-MM-DD | Cursor Prototype | 2 | 1 | 3 | No | 4 | Yes | "Clients love interacting with live HTML without app installs." | PASS | PASS |

---

## 5. Decision gate protocol

At the end of Week 8:
- **Proceed to build billing (P1-c):** If `>= 6` pilots have `Gate 1 Pass = PASS` and `>= 2` pilots have `Gate 2 Pass = PASS`.
- **Kill / Pivot:** If `< 6` pilots used it repeatedly, or `< 2` say they would pay US$15/month, stop immediately before implementing Stripe/web billing. Re-evaluate customer archetype or revert to personal utility as documented in `mrr-plan.md`.
