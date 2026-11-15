# FastShared Publications

## Hero

### Headline
Send the link. Your iPhone tells you when the client opens it.

### Sub-headline
Publish the report, proposal, or prototype your AI made as a live link. Update it without changing the URL. Revoke it whenever you want.

### Calls to action
- **Primary:** Publish a link
- **Secondary:** View live demo

---

## Benefits

### 1. Instant publication for AI deliverables
Exported an interactive dashboard from Claude? Built a prototype in Cursor or generated a client report in Codex? Drop the HTML, PDF, or ZIP onto FastShared. It unpacks cleanly on an isolated origin and gives you a stable, shareable URL in seconds. No terminal wrangling, no repository setup, no server configuration.

### 2. Browser open alerts delivered to your pocket
Stop wondering if your proposal is sitting unread in an inbox. When the link is opened in a real desktop or mobile browser, a lightweight beacon fires and your iPhone delivers a quiet alert: *Opened in a browser*. Automated link unfurlers from Slack, WhatsApp, and iMessage are filtered out by design, so you hear when the page is opened in a real browser — link previews from Slack, WhatsApp, and iMessage don't count.

### 3. Purposeful control without eternal clutter
You stay in charge of the presentation lifecycle. Update your work under the same link so the client never sees a broken bookmark. Set a link to expire, or revoke access immediately when the engagement closes. Free publications expire cleanly after seven days; Pro publications remain active as long as your membership is current.

---

## How it works

### Step 1: Stage your file
Drag your single HTML file, compiled PDF, or zipped bundle into the browser uploader or push it from the CLI.

### Step 2: Send the link
Copy the generated short link to your clipboard and paste it into your email, Slack, or message thread.

### Step 3: Receive the alert
When the link is opened in a browser, your iPhone pings you. You hear when the page is opened in a real browser — link previews from Slack, WhatsApp, and iMessage don't count.

---

## Honest comparison

Independent professionals have several ways to share deliverables. Here is how FastShared compares to the most common alternatives for sharing interactive HTML and documents.

*(Competitor data verified on November 14, 2026.)*

| Feature | sharable.link | tiiny.host | DocSend | FastShared |
| :--- | :--- | :--- | :--- | :--- |
| **Price** | Free | Free to US$18/mo ([tiiny.host/pricing](https://tiiny.host/pricing/)) | US$15/mo ([docsend.com/pricing](https://www.docsend.com/pricing/)) | Free or US$15/mo (US$144/yr) |
| **Target format** | Static files and links | Static web pages and PDFs | PDF decks, docs, spreadsheets | HTML, ZIP bundles, PDFs |
| **Open alerts** | No notification system ([privacy policy](https://sharable.link/privacy)) | Solo tier only (US$18/mo) | Email and dashboard alerts | iPhone push alerts on all tiers |
| **Bot filtering** | N/A | Basic analytics | Document preview tracking | Dedicated unfurler filter |
| **Interactive HTML** | Limited preview | Yes | No (converts to slides/PDF) | Full browser execution |
| **Host isolation** | Shared domain | Shared or custom subdomain | Proprietary viewer app | Isolated origin per tenant |
| **Link updates** | Version history included | Re-upload replaces content | File replacement supported | Same-URL updates |

### Detailed breakdown

- **sharable.link**  
  [sharable.link](https://sharable.link/) is a great free utility that supports password protection, versions, and link revocation. However, its architecture does not notify the sender when a link is visited, and it explicitly states that it does not track visitors ([source: privacy policy](https://sharable.link/privacy)). If you only need free hosting without knowing when the recipient viewed the file, it is a solid choice.

- **tiiny.host**  
  [tiiny.host](https://tiiny.host/pricing/) is well-regarded for simple static web hosting. Its free tier is limited to a single project with a 3 MB file cap and Tiiny branding. To receive real-time open alerts and access custom security controls, you must subscribe to the Solo plan, which costs US$18 per month (or US$13 per month billed annually at US$156 per year; [source: helpdesk pricing](https://helpdesk.tiiny.host/en/article/pricing-plans-1i3vkky/)). FastShared focuses specifically on client deliveries and includes phone push notifications directly in the workflow.

- **DocSend**  
  [DocSend](https://www.docsend.com/pricing/) is an industry standard for sales teams and venture pitch decks, starting at US$15 per user per month on monthly billing (or US$10 per user per month billed annually). It offers granular page-by-page analytics and eSignatures for PDFs. However, DocSend cannot host interactive web applications, client-side dashboards, or multi-file HTML packages produced by modern AI coding assistants. FastShared is designed specifically for that interactive medium.

---

## Frequently asked questions

### 1. How does FastShared know when the link is opened in a browser?
When the page renders in a web browser, a tiny first-party JavaScript beacon confirms that real DOM rendering occurred. This prevents false alarms from web crawlers. Because the beacon confirms browser execution rather than identity, the alert states *Opened in a browser*.

### 2. Will sharing the link in Slack, WhatsApp, or iMessage trigger a false notification?
No. Messaging apps send background crawler bots to generate link previews and Open Graph cards. FastShared detects these known automated user agents and serves the preview metadata without triggering an open event. Your phone only alerts you when the page is rendered in a real browser — link previews don't count.

### 3. Can I share multi-file HTML bundles like Vite or Tailwind projects?
Yes. Compress your project folder into a standard ZIP archive containing an `index.html` file at the root. FastShared extracts the assets securely on an isolated subdomain, preserving relative links for stylesheets, scripts, and media.

### 4. How does link expiration work?
Free publications expire automatically after seven days. Pro publications stay online as long as your subscription is active. If you cancel Pro, you receive 30 days of notice and export time before files are removed. You can also manually revoke any link at any moment.

### 5. Does my client need to create an account or install an app?
No. Your recipient clicks the link and views your work directly in their browser on desktop, tablet, or phone. The link is the credential. Only the sender needs an account to manage publications and receive alerts.

### 6. Where is user content hosted?
User deliverables are hosted on a dedicated, isolated domain rather than our primary web apex. This isolates security contexts and cookies, protecting your visitors and preventing malicious scripts from affecting other users.
