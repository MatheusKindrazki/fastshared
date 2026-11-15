---
title: "Password Protect an HTML Link | FastShared"
description: "Protect sensitive client HTML files, reports, and prototypes with passwords. Step-by-step tutorials using client-side crypto, web servers, and links."
---

# How to password protect an HTML file link

When delivering an executive audit, financial report, or proprietary prototype, you cannot treat the work like public web content. Even if a link is unlisted, search engines, browser extensions, or forwarding chains can inadvertently expose sensitive client data.

Adding password protection provides an essential security barrier. 

Whether you need a free, zero-server solution today or a streamlined client delivery platform with open alerts, here is how to password-protect an HTML file link.

---

## Method 1: Client-side AES-256 encryption with Staticrypt (Free, no server)

The cleanest way to password-protect a standalone HTML file without configuring a web server is through client-side encryption using an open-source tool like Staticrypt.

### How it works:
Staticrypt takes your raw HTML file and encrypts its contents using AES-256-GCM. It generates a new HTML file containing an encrypted string and a clean, responsive password entry form. When your client opens the link and enters the password, the browser's native Web Crypto API decrypts the HTML entirely in memory and renders the page.

### Step-by-step tutorial:
1. Ensure Node.js is installed on your computer, then install Staticrypt globally:
   ```bash
   npm install -g staticrypt
   ```
2. Navigate to the folder containing your client deliverable:
   ```bash
   cd ~/Documents/client-reports/
   ```
3. Run the encryption command, specifying your passphrase and output file:
   ```bash
   staticrypt report.html "ClientSecretKey2026!" -o protected.html --title "Confidential Client Audit"
   ```
4. Upload `protected.html` to any static host (Cloudflare Pages, Netlify Drop, or S3).
5. Share the generated link with your client and send the password through a separate communication channel (such as SMS or Signal).

### Trade-offs:
- **Pros:** Completely serverless. Works on any static file host.
- **Cons:** Anyone who obtains the URL downloads the encrypted payload. If someone uses a weak password, it could theoretically be attacked offline. In addition, static hosting provides no notification when the client successfully decrypts and views the page.

---

## Method 2: Server-side HTTP Basic Auth

For maximum security, you may want a server to gate access before sending any file bytes to the client.

### Step-by-step with Nginx:
1. Generate an encrypted password file using `htpasswd`:
   ```bash
   sudo htpasswd -c /etc/nginx/.htpasswd clientuser
   ```
2. Configure your Nginx server block for the client directory:
   ```nginx
   location /client-deliverables/ {
       auth_basic "Confidential Access Required";
       auth_basic_user_file /etc/nginx/.htpasswd;
       try_files $uri $uri/ =404;
   }
   ```
3. Reload Nginx (`sudo systemctl reload nginx`).

### Trade-offs:
- **Pros:** The server will not release a single byte until valid credentials are provided.
- **Cons:** Browser-native basic auth prompts look outdated and can intimidate non-technical stakeholders. Maintaining server infrastructure and credential files for every individual client engagement quickly becomes cumbersome.

---

## Method 3: Dedicated link platforms and FastShared roadmap

If you prefer a managed sharing utility, several platforms offer password protection without terminal configuration:

- **sharable.link:**  
  [sharable.link](https://sharable.link/) is a helpful free service that offers password protection, version history, and manual link revocation. However, its architecture does not notify the sender when a link is opened or visited ([source: sharable.link privacy](https://sharable.link/privacy)).

- **FastShared roadmap transparency:**  
  FastShared currently supports instant publishing for HTML, PDF, and ZIP deliverables, complete with automated bot filtering and push notifications to your iPhone when your work renders in a browser.  
  
  **Password-protected links are scheduled for our upcoming P2 release.** Once rolled out to Pro subscribers, you will be able to set a passphrase on any publication. When your client enters the password and renders the deliverable, your iPhone will notify you immediately.

---

## Best practices for sharing password-protected links

1. **Send credentials out-of-band:** Never include the password in the same email or message as the link. If an email is forwarded or compromised, the deliverable remains secure.
2. **Combine passwords with expiration:** Passwords prevent unauthorized viewing, but expiration prevents forgotten files from living on the web indefinitely. Set a strict expiration window (such as seven days for drafts).
3. **Revoke access after sign-off:** Once a client engagement is complete or the invoice is settled, revoke the link immediately.

---

## Frequently asked questions

### Can search engines index password-protected HTML files?
No. Because client-side encrypted files require user interaction to decrypt and server-side protected files return a `401 Unauthorized` header to crawlers, search engines cannot index the underlying text.

### What happens if the client forgets the password?
With client-side tools like Staticrypt, there is no password recovery. You must re-encrypt the file with a new password and resend the link or provide the updated passphrase.

### Does password protection work for multi-file web bundles?
Yes. When using a managed platform or server-side auth, credentials protect the entire directory, including all associated stylesheets, scripts, and media.

---

## Deliver client work with confidence and clarity

Publish interactive HTML deliverables as clean, temporary web links and get notified on your iPhone the moment they render.

[Publish a link on FastShared](https://fastsha.red)
