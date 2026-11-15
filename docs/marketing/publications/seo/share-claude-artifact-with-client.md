---
title: "Share Claude Artifact with a Client | FastShared"
description: "Step-by-step guide to exporting and sharing interactive Claude HTML artifacts with clients as standalone links, plus tracking when they open it."
---

# How to share a Claude artifact with a client

Anthropic's Claude Artifacts feature has transformed consulting workflows. In minutes, you can prompt Claude to build an interactive ROI calculator, an executive dashboard, a UX prototype, or a comprehensive data visualization.

However, getting that artifact in front of a paying client remains unexpectedly clumsy.

If you share the public Claude conversation link, your client is forced to create an Anthropic account, sees your internal prompting history, and views your deliverable crammed into a sidebar preview. If you download the raw HTML file and email it as an attachment, non-technical stakeholders struggle to open it from their local file system.

Here is how to extract, prepare, and share an interactive Claude artifact as a standalone, professional link that alerts your iPhone when it is opened in a real browser.

---

## Step 1: Export the artifact from Claude

When Claude generates an interactive artifact (HTML, SVG, or React component):

1. Look at the upper-right corner of the Artifact preview card inside Claude.
2. Click the **Code** toggle to view the underlying markup.
3. Click the **Download** icon (or copy the entire code block into an editor like VS Code or TextEdit).
4. Save the file locally as `index.html`.

### Verifying standalone execution
Open `index.html` in your local browser to ensure it runs independently. Claude usually bundles standalone HTML artifacts with CDN scripts:
- **Tailwind CSS:** `<script src="https://cdn.tailwindcss.com"></script>`
- **React and Babel:** `<script src="https://unpkg.com/react..."></script>`
- **Lucide Icons:** `<script src="https://unpkg.com/lucide..."></script>`

If the component fails to render locally, verify that external CDN scripts are not blocked by local ad-blockers or missing opening `<script>` tags.

---

## Step 2: Hosting the artifact without FastShared (The DIY alternatives)

If you need a free way to share the artifact immediately, here are two common self-hosting methods:

### Option A: GitHub Gist + HTML Preview
1. Go to [gist.github.com](https://gist.github.com) and create a public Gist named `index.html`.
2. Paste the artifact code and save the Gist.
3. Prepend `https://htmlpreview.github.io/?` to your raw Gist URL.
4. *Trade-offs:* The URL is long, looks unprofessional, and third-party preview proxies occasionally drop external CDN requests.

### Option B: Netlify Drop
1. Create a local folder called `artifact` and place `index.html` inside.
2. Visit `app.netlify.com/drop` (requires a Netlify account).
3. Drag the folder into the deployment zone. Netlify provides an auto-generated subdomain.
4. *Trade-offs:* Great for deployment, but requires managing a cloud dashboard. More importantly, Netlify does not notify you when the client opens the link.

---

## Step 3: Publish with FastShared and receive open alerts

FastShared provides an instant, client-ready publishing workflow built specifically for consultants delivering AI-generated work.

1. **Publish:** Drag your exported Claude `.html` file onto [fastsha.red](https://fastsha.red) or run `fastshared publish ./index.html`.
2. **Deliver:** Copy the clean, short link to your clipboard and paste it into your email, Slack channel, or client portal.
3. **Get notified:** The moment your client opens the link in their web browser, your iPhone pings you with a push notification: *Opened in a browser*.

### Why this works better for client deliverables:
- **Client focus:** Your client sees only the interactive deliverable in full-screen view. No Claude chat interface, no prompt history, and no account required.
- **Unfurler filtering:** When you share the link in Slack or WhatsApp, preview bots fetch metadata without triggering an alert. You only get notified when a real browser renders the page.
- **Controlled lifecycle:** Free deliverables expire after seven days, ensuring temporary drafts do not linger on the web. Pro subscribers keep deliverables live with optional manual revocation at any time.

---

## Best practices for client-facing Claude artifacts

1. **Add custom branding:** Replace default placeholder text with your client's brand colors, typography, and company name before exporting.
2. **Check mobile responsiveness:** Test the artifact on your phone before sending. Many executives review deliverables on mobile devices.
3. **Include a call to action inside the artifact:** Add a contact button or next-steps banner at the bottom of the artifact linking back to your email or calendar.

---

## Frequently asked questions

### Does the client need a Claude or Anthropic account?
No. Once published through FastShared, your artifact is hosted as a standard web page. Anyone with the link can view and interact with it in any modern browser.

### Can I share multi-file artifacts or React builds?
Yes. If your artifact relies on multiple files, local images, or a compiled build directory (such as a Vite project), compress the files into a standard `.zip` archive containing `index.html` at the root. FastShared unpacks and hosts the bundle automatically.

### Can I update the artifact after sending the link?
With FastShared Pro, you can push updates to the same URL, allowing you to incorporate client feedback without sending a new link.

---

## Deliver your next artifact with confidence

Stop sending screenshot galleries or raw attachments. Host your Claude artifact as a live web link and hear the moment it is opened in a real browser.

[Publish your Claude artifact on FastShared](https://fastsha.red)
