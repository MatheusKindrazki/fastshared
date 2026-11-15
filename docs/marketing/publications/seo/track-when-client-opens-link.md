---
title: "Track When a Client Opens a Link | FastShared"
description: "Track when clients open your proposals, deliverables, and reports without invasive tracking pixels or false alarms from Slack and WhatsApp bots."
---

# How to track when a client opens a link

Every consultant and freelancer knows the silence that follows sending an important proposal, audit report, or contract. 

You finish the work, email the link, and enter a waiting period. You hesitate to follow up too quickly because you do not know if the client has had time to review it. At the same time, waiting too long risks losing momentum.

To time your follow-up perfectly, you need to know when your link is opened. However, tracking link opens in modern messaging environments is surprisingly difficult.

---

## Why traditional link tracking is broken

Most link tracking tools were built a decade ago and struggle with modern privacy protections and messaging apps.

### 1. Email tracking pixels are unreliable
Traditional email tracking relies on a hidden 1x1 pixel image embedded in the email body. When Apple introduced Mail Privacy Protection (MPP), Apple Mail began automatically pre-fetching remote images through proxy servers before the user even opened the email. This triggers immediate false positives for any recipient reading mail on macOS or iOS.

### 2. Standard URL shorteners trigger false alarms
If you use standard link shorteners or redirect trackers, you run into the link unfurler problem. Whenever you paste a link into Slack, Microsoft Teams, WhatsApp, or iMessage, the messaging platform dispatches an automated crawler to inspect the destination and generate an Open Graph preview card. 

Standard trackers record that HTTP request as a visitor. You get an alert saying your link was viewed when all that happened was a chat bot fetching preview metadata.

---

## How to build reliable open tracking (The DIY method)

To track opens accurately without false alarms, you must shift tracking from the initial HTTP redirect to the browser rendering phase. A full web browser executing the page runs JavaScript and renders the DOM; an unfurler bot usually just fetches the initial HTML and exits.

If you host your own HTML deliverables, you can add a lightweight JavaScript beacon to your page that calls a webhook endpoint (such as a Discord or Slack webhook):

```html
<script>
  window.addEventListener('DOMContentLoaded', () => {
    // Basic bot suppression
    const isBot = /bot|crawler|spider|crawling/i.test(navigator.userAgent);
    if (isBot) return;

    // Fire beacon after real DOM render
    const payload = JSON.stringify({
      event: 'deliverable_opened',
      timestamp: new Date().toISOString(),
      screen: `${window.innerWidth}x${window.innerHeight}`
    });

    if (navigator.sendBeacon) {
      navigator.sendBeacon('https://your-webhook-endpoint.com/log', payload);
    } else {
      fetch('https://your-webhook-endpoint.com/log', {
        method: 'POST',
        body: payload,
        keepalive: true
      });
    }
  });
</script>
```

### Limitations of the DIY approach:
- You must maintain your own serverless function or webhook endpoint to process the alerts.
- Setting up push notifications on your phone requires configuring third-party notification apps like Pushover or configuring a custom bot.
- Sophisticated bots (like headless Chrome previewers) can still trigger the script unless you maintain an updated blocklist of bot IP ranges and user agents.

---

## Tracking opens effortlessly with FastShared

FastShared is designed to solve link tracking for client deliverables out of the box.

When you publish a deliverable through FastShared, open tracking is built directly into the delivery pipeline:

1. **Upload your deliverable:** Drag your HTML file, PDF, or ZIP bundle to [fastsha.red](https://fastsha.red).
2. **Send your link:** Copy the generated short link and send it via email, WhatsApp, or Slack.
3. **Get notified on your phone:** When the recipient loads the page in a browser, your iPhone receives an instant push notification: *Opened in a browser*.

### How FastShared prevents false positives:
- **Dedicated bot filtering:** FastShared identifies and filters automated link unfurlers from WhatsApp, Slack, iMessage, Telegram, LinkedIn, and corporate security scanners. They receive preview metadata without triggering an open event.
- **Client-side render confirmation:** An alert only fires when the page actually renders inside a genuine web browser.
- **Push notification directly to your pocket:** You do not need to check a web dashboard or refresh an analytics feed. Your phone alerts you quietly the moment the deliverable is viewed.

---

## Respecting client privacy

Effective tracking is about timing your follow-ups, not spying on your clients. 

FastShared avoids invasive surveillance:
- No tracking cookies are placed in your client's browser.
- Deliverables do not harvest personal data, browsing history, or biometric signals.
- Alerts state *Opened in a browser* because the system confirms genuine browser rendering rather than building an invasive behavioral dossier.

This transparent posture ensures you remain fully compliant with modern data privacy expectations while still knowing when your deliverable is rendered in a browser.

---

## Frequently asked questions

### What does the notification say when a link is opened?
Your iPhone or Mac receives a push notification saying: *Opened in a browser*.

### Will pasting the link in Slack or WhatsApp alert me?
No. FastShared filters out preview crawlers from Slack, WhatsApp, iMessage, and similar platforms. You will only receive a notification when the link is opened and rendered in a real browser — link previews don't count.

### How many open alerts can I receive?
The Free tier includes three open notifications per publication. The Pro tier includes unlimited open alerts.

---

## Take the guesswork out of client delivery

Know the moment your proposal or report is opened in a real browser. Share your next deliverable with FastShared and get open alerts delivered directly to your iPhone.

[Publish a link on FastShared](https://fastsha.red)
