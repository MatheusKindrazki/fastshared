# FastShared — Launch Kit

Outreach assets, community launch posts, direct message templates, and pilot invitation copy.

---

## 1. Hacker News — Show HN

### Timing
Post on Tuesday or Wednesday between 8:00 AM and 9:00 AM ET.

### Title
```text
Show HN: FastShared – My iPhone pings when a client opens the proposal Claude wrote
```
*(79 characters — within HN's 80-character ceiling)*

### Post body
```text
I do freelance consulting and build a lot of client deliverables—interactive dashboards, UX prototypes, and proposal audits—using Claude, Cursor, and ChatGPT. 

The delivery workflow was always awkward: emailing an .html file breaks external scripts and local assets for non-technical clients; sharing a Claude conversation link requires an Anthropic login and leaks the prompt history; and traditional hosts like Vercel or Netlify turn a simple client deliverable into a permanent git repository. On top of that, I never knew whether the client actually opened the link or if it was sitting unread in their inbox.

I built FastShared to solve this for myself.

You drag an HTML file, compiled PDF, or zipped multi-file bundle into the web uploader or push it from the CLI (`fastshared publish ./proposal.html`). You get a clean short link on an isolated domain. When your client loads the page in a browser, your iPhone receives a push alert: "Opened in a browser".

How the tracking works without false alarms:
Pasting a link into Slack, WhatsApp, or iMessage triggers automated preview crawlers (unfurlers) that fool standard URL shorteners into logging an open. FastShared filters out these automated user agents and fires the alert only from a first-party beacon after the browser renders the DOM. It alerts on browser rendering, not identity, which is why the notification says "Opened in a browser".

Tech stack:
- Backend: Hono on Cloudflare Workers, Neon Postgres for metadata, KV for rate limits and deduplication.
- Storage: Cloudflare R2 on dedicated isolated origins per tenant (to prevent user HTML scripts from touching session cookies).
- Client: Native iOS/macOS utility built in SwiftUI, receiving alerts via APNs.
- CLI: Lightweight Node package for terminal publishing.

Pricing model:
Free tier: 1 active publication, 7-day expiration, 3 open alerts per deliverable.
Pro tier: US$15/month or US$144/year for multiple publications (2 GB storage), publications kept active while subscribed, and unlimited open alerts. Features like same-URL updates, password protection, and MCP integration are on the roadmap for P2.

Live site: https://fastsha.red

Would love feedback on the delivery mechanics and the bot-filtering approach.
```

---

## 2. Reddit — r/freelance

### Compliance note
`r/freelance` enforces a strict **Rule 1: No Self-Promotion, Advertising, or Link-Dropping**. Direct promotional links, portfolio pitches, and "check out my app" posts result in immediate deletion and account bans. Community guidelines require 100% text-native, educational value without outbound links.

### Strategy
Post a comprehensive retrospective analyzing client communication gaps, link unfurlers, and proposal tracking mechanics. Zero links in the body. If commenters ask what tool is being used, answer transparently and minimally in the comments.

### Post title
```text
Why sending HTML/PDF proposals as links triggers false "reads" (and how to fix your delivery timing)
```

### Post body
```text
Over the past year, more of my client deliverables moved from static documents to interactive formats: interactive data models from Claude, live prototype audits from Cursor, and interactive dashboards.

One recurring frustration was the "proposal black hole": sending a proposal or deliverable over email or Slack and having zero idea if the client opened it, while wondering when to follow up without being annoying.

I spent time testing different tracking methods and realized almost all off-the-shelf tracking breaks in subtle ways today. Here is what I learned that might save other freelancers some headache:

1. Email open tracking pixels are mostly dead.
Apple's Mail Privacy Protection (MPP) automatically routes remote images through Apple proxy servers before the recipient even touches their inbox. If your client uses Apple Mail on iPhone or Mac, you get an instant "opened" notification within seconds of sending, regardless of whether the message was opened in a mail client.

2. Messaging apps fool URL shorteners.
If you use standard tracking shorteners (like Bitly or generic redirect links) and paste them into Slack, WhatsApp, iMessage, or Microsoft Teams, the chat application immediately dispatches a crawler bot to fetch Open Graph cards and preview metadata. The shortener counts that GET request as a visitor. You get excited thinking the client opened your proposal, but it was just Slack's crawler.

3. The only reliable check is DOM render confirmation.
A link preview bot fetches raw HTML, parses meta tags, and leaves. A real web browser executes JavaScript and renders the page. Shifting the signal from the HTTP redirect to an in-browser beacon (using `navigator.sendBeacon` after DOMContentLoaded) stops preview bots from triggering false alarms.

4. Client friction kills engagement.
Forcing an executive client to log into a platform (like Figma, Notion, or DocSend) just to review a short report adds unnecessary friction. The best delivery format is a standalone link that works in any mobile or desktop browser without sign-up.

Curious how others here handle this: do you stick to static PDFs, or are you delivering interactive web deliverables to clients? How do you gauge whether the client actually reviewed your work before following up?
```

---

## 3. Reddit — r/consulting

### Compliance note
`r/consulting` enforces **Rule 4: Professional Conduct and No Spam / Low-Quality Self-Promotion**. The community strictly adheres to the 9:1 value-to-promotion ratio. Pure product pitches are removed immediately. Content must address real consulting delivery workflows and client management.

### Strategy
Share an operational discussion on modernizing technical deliverable handoffs (moving from static slide decks to interactive AI-generated artifacts) and navigating the tracking etiquette.

### Post title
```text
Moving client deliverables from slide decks to interactive HTML: delivery workflows and visibility
```

### Post body
```text
In technical and management consulting, executive slide decks have long been the default deliverable format. Over the last six months, our deliverables for technical audits, ROI models, and workflow prototypes have increasingly shifted to interactive HTML applications generated with Claude and coding assistants.

Clients consistently respond better to an interactive model where they can adjust assumptions and test scenarios themselves compared to twenty static slides.

However, the delivery infrastructure for interactive deliverables has lagged behind:

1. Email attachments fail for non-technical stakeholders.
Sending an HTML file via email often leads to non-technical stakeholders trying to open it in text editors or hitting local browser security errors because scripts cannot run from local `file://` directories.

2. Heavy enterprise platforms add too much friction.
Putting a lightweight five-page audit or interactive model behind an enterprise portal or data room login slows down executive review. Senior stakeholders frequently ignore links that require creating a new account or remembering a password.

3. Tracking executive engagement without being invasive.
DocSend works well for pitch decks, but it flattens interactive web applications into static images. Conversely, traditional URL tracking shorteners fire false positives the moment you paste a link into Slack, WhatsApp, or Teams because preview crawlers hit the URL automatically.

We moved to hosting deliverables as lightweight standalone links that execute safely on isolated origins and fire a quiet browser-render beacon when opened. Knowing that the link was opened in a browser at 8:00 AM gives you the context you need for a follow-up call at 10:00 AM, without guessing whether the email was lost in their inbox.

For those running independent or boutique practices: are you seeing client demand shift toward interactive deliverables, and how are you managing the hosting and review tracking?
```

---

## 4. Direct Messages — 3 variations

Targeted at consultants and freelancers who posted publicly on Twitter/X, Bluesky, or LinkedIn about client ghosting, wondering if a proposal was seen, or struggling to share HTML artifacts.

### Variation 1: The proposal follow-up dilemma (General freelance/consulting)
```text
Saw your post about waiting on client feedback. That silence after sending a proposal is maddening—especially when you can't tell if they opened it or if it landed in spam. 

I got tired of guessing, so I built a small utility called FastShared (https://fastsha.red). You upload your HTML or PDF proposal as a link, and your iPhone pings you the moment they open it in a browser (filters out Slack/WhatsApp preview bots so no false alarms). 

Free tier gives you 3 open alerts per send. If you want to try it on your next proposal, let me know how it works for you.
```

### Variation 2: Technical deliverables & Claude/AI artifacts
```text
Saw your tweet about exporting prototypes from Claude for a client. Sharing raw HTML attachments with clients is always a mess—they either can't open them or the local scripts fail to load.

I built a tool called FastShared (https://fastsha.red) specifically for this. You drag the HTML or ZIP bundle, get a clean link, and your iPhone alerts you when the client actually renders it in their browser. 

Would love to give you 3 months of Pro on the house if you want to test it on your client sends. Happy to send over an invite if interested.
```

### Variation 3: DocSend frustration / PDF alternatives
```text
Saw your note about DocSend pricing and clunky slide viewers. If you're delivering interactive reports or dashboards, DocSend is frustrating because it flattens everything into static pages.

I built FastShared (https://fastsha.red) as a focused alternative for consultants: host real interactive HTML, PDFs, or ZIPs, and your phone gets an alert when the client opens it in a browser, without charging $45/mo for basic features. 

Drop me a note if you'd like to test-drive it on your next client delivery.
```

---

## 5. Pilot Invitation Email

### Subject
```text
Testing FastShared: 3 months of Pro for your client deliverables
```

### Email body
```text
Hi [Name],

I've been following your consulting work on [specific topic/platform] and noticed you frequently deliver technical work and interactive reports to clients.

I'm the founder of FastShared. We built a native utility that turns interactive HTML deliverables, Claude artifacts, and client proposals into live links—and sends a quiet alert to your iPhone the moment your client opens the page in their browser.

We filter out Slack, WhatsApp, and iMessage preview bots, so you hear when the page is opened in a real browser — link previews don't count.

We are selecting 10 active consultants to participate in our private launch pilot. Here is the offer:

1. Three months of FastShared Pro entirely free (unlimited publications, 2 GB storage, white-label links, and unlimited browser open alerts).
2. Direct personal support for any deliverable formatting or custom setups.

In exchange, all I ask for are two short conversations:
- A 15-minute onboarding call to set up your workflow.
- A 20-minute feedback call after you have used it on real client sends for two weeks.

If you are currently sending deliverables or proposals to clients and want to stop guessing whether they opened them, reply to this email or grab a quick time on my calendar here: [Calendar Link].

Thanks for your time,

Matheus Kindrazki  
Founder, FastShared  
https://fastsha.red
```
