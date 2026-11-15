---
title: "Share an HTML File as a Link | FastShared"
description: "Learn how to turn any standalone HTML file into a live web link for clients using static hosts, local tunnels, or FastShared with browser open alerts."
---

# How to share an HTML file as a link

Emailing an `.html` file directly to a client is one of the most frustrating experiences in consulting. 

When a non-technical client double-clicks an email attachment, their computer often opens it in a code editor, displays a raw text dump, or launches it from a local `file://` path. From there, security policies block external fonts, scripts, and embedded assets. The client sees broken styles, assumes the deliverable is defective, and sends a confused email.

To present an HTML deliverable professionally, you need to share it as a live web link. This guide walks through three distinct methods: free static hosting, local tunnels, and instant publication with browser open alerts.

---

## Method 1: Host the HTML file on a static cloud host (Free, persistent)

If you have a GitHub account or access to a cloud platform, you can deploy your HTML file to a free static host like GitHub Pages or Cloudflare Pages.

### Step-by-step with Cloudflare Pages:
1. Log in to the Cloudflare dashboard and navigate to **Workers & Pages**.
2. Select **Create application** > **Pages** > **Upload assets**.
3. Create a new folder on your computer named `public` and save your deliverable as `index.html` inside it.
4. Drag the `public` folder directly into the Cloudflare upload dropzone.
5. Click **Deploy site**. Cloudflare generates a production URL ending in `.pages.dev`.

### When to use this approach:
Static hosting is great for permanent project documentation or public marketing sites. 

### Limitations:
- **No notification when viewed:** You have no idea when the client opens the link unless you embed Google Analytics, which ad blockers frequently disable.
- **Permanent public record:** The URL remains active until you manually remember to log into your cloud dashboard and delete the deployment.
- **Setup overhead:** Creating repositories or project folders for a single client proposal creates unnecessary digital clutter.

---

## Method 2: Share instantly via a local tunnel (Quick, temporary)

If you are on a live client call or need to demo an interactive prototype immediately without uploading files to a third-party server, you can host the file locally and tunnel it.

### Step-by-step using Python and Cloudflare Quick Tunnels:
1. Open your terminal and navigate to the directory containing your HTML file:
   ```bash
   cd ~/Documents/client-proposals/
   ```
2. Start a lightweight local HTTP server:
   ```bash
   python3 -m http.server 8080
   ```
3. In a separate terminal tab, generate a secure public HTTPS tunnel without creating an account:
   ```bash
   cloudflared tunnel --url http://localhost:8080
   ```
4. Copy the temporary `trycloudflare.com` URL printed in the terminal and send it to your client.

### Limitations:
- The link dies the instant you close your laptop, enter sleep mode, or terminate the terminal process.
- Tunnel URLs look random and can trigger security warnings in corporate email filters.

---

## Method 3: Instant publication with FastShared (Client-ready, notified)

When you deliver proposals, audit reports, or interactive prototypes to paying clients, you need a workflow that is faster than cloud deployments, cleaner than terminal tunnels, and keeps you informed.

FastShared turns any HTML file, PDF, or zipped bundle into a clean web link in seconds, with built-in open tracking.

### Step-by-step:
1. **Stage your file:** Drag and drop your `.html` file onto [fastsha.red](https://fastsha.red) or run `fastshared publish ./proposal.html` from your command line.
2. **Send the link:** The short URL is immediately placed on your clipboard. Paste it into your client message or email.
3. **Receive the alert:** When your client opens the link in their desktop or mobile browser, your iPhone receives a push alert: *Opened in a browser*.

### Key advantages:
- **Filtered open alerts:** Automated link previews from Slack, WhatsApp, and iMessage are filtered out. You are only notified when a real browser renders the page.
- **Isolated sandbox:** Deliverables run on a dedicated, isolated domain, protecting your visitors and personal infrastructure from script vulnerabilities.
- **Automatic expiration:** Free links expire in seven days. Pro links live while your subscription is active. You can revoke any link at any moment.

---

## Best practices before sending an HTML link to a client

1. **Inline critical assets:** If your HTML relies on small SVG icons or custom styling, inline them or link to trusted CDNs (like unpkg or cdnjs) so external stylesheets resolve without broken paths.
2. **Test responsive viewport tags:** Confirm your HTML includes `<meta name="viewport" content="width=device-width, initial-scale=1.0">`. Many executive stakeholders open proposal links on mobile devices first.
3. **Check link previews:** Paste the link into a private test channel to ensure the Open Graph title and summary reflect your work accurately.

---

## Frequently asked questions

### Will the recipient see an installation prompt?
No. Recipients open the link in their standard web browser (Chrome, Safari, Firefox, Edge). They do not need to install an app or register.

### Can I share an HTML file that has external CSS and JavaScript files?
Yes. Put your `index.html`, stylesheet, and scripts in a folder, compress it into a `.zip` archive, and upload the ZIP. FastShared unpacks the archive securely and serves it as a complete website.

### How do I stop a client from accessing the link later?
You can click **Revoke** in your dashboard or run `fastshared revoke <slug>` in your terminal. The link immediately returns a 410 Gone status.

---

## Publish your deliverable in seconds

Stop sending clunky email attachments. Upload your HTML file to FastShared, get a clean link, and hear the moment the page is opened in a real browser.

[Publish a link on FastShared](https://fastsha.red)
