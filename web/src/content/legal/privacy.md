# DRAFT — requires founder/legal review

# Privacy Policy — FastShared

> **Summary of changes vs current `web/src/pages/privacy.astro` (v1.2, 24 April 2026):**
> 1. **Web Publications data processing added:** Documents the processing and storage of files published to `p-<slug>.fastsha.red` in a dedicated Cloudflare R2 bucket (`fastshared-publications`) and associated structural metadata in Neon Postgres (`publication`, `publication_version`, `publication_file`, `publication_open`).
> 2. **Publication Open Beacon detailed:** Discloses how real-browser opens are recorded for publications: a cryptographic SHA-256 hash of a local visitor token combined with a secret server pepper (`visitor_hash`), plus the timestamp (`opened_at`), deduplicated once per 24 hours per visitor/publication/version. For inline PDFs, server-side document request headers with IP hashing are used. Clarifies that there is **no cross-site tracking**, no third-party profiling, and no advertising cookies.
> 3. **Web passwordless authentication:** Documents collection of email addresses for passwordless magic links (`POST /v1/auth/email/start`), which issue device tokens stored strictly in browser `localStorage` (with no domain-wide `.fastsha.red` session cookies).
> 4. **Paddle added as Sub-processor & Merchant of Record:** Details web billing processing via Paddle.com. FastShared stores entitlement records (customer ID, subscription status, period end dates), while sensitive credit card, banking, and Pix payment details are processed directly by Paddle and never touch FastShared servers.
> 5. **Sub-processors updated:** Adds Paddle to the official sub-processors register alongside Cloudflare, Neon, and Apple (and note on transactional email delivery).
> 6. **Updated retention schedules:** Details the lifecycle for publications (Free: 7 days + 24h hard delete; Pro: persistent while active; canceled Pro: 30-day notice period before permanent deletion).

---

**Effective Date:** [Target: November 2026] · Version 2.0-draft  
**Data Controller:** Matheus Kindrazki (Individual Developer / Sole Operator, Curitiba, Paraná, Brazil)  
**Contact:** `privacy@fastsha.red` · `support@fastsha.red`

---

## 1. Overview and Core Principles

FastShared is built on a simple philosophy: **provide fast, reliable, privacy-first file sharing and web publishing with zero surveillance capitalism**.

We do not track your browsing habits across the web, we do not sell your personal data, we do not use third-party behavioral analytics or advertising trackers, and we do not monetize your audience or clients. This Privacy Policy explains what data we process, why we process it, where it is stored, how long it is retained, and your rights under global privacy regulations, including the European Union General Data Protection Regulation (GDPR) and the Brazilian General Data Protection Law (LGPD — Lei Geral de Proteção de Dados).

---

## 2. Who is the Data Controller?

The data controller for personal data processed through FastShared is:
- **Matheus Kindrazki**, operating as an individual software developer and sole proprietor based in Curitiba, State of Paraná, Brazil.
- **Contact Email:** `privacy@fastsha.red`

If the operations of FastShared are transferred to a dedicated corporate entity, this policy will be promptly updated with the new entity’s legal name, CNPJ/registration details, and registered office.

---

## 3. What Data We Collect and Process

We process only the minimum technical data necessary to provide file transfers, host web publications, process subscriptions, and safeguard service stability:

### 3.1. Content You Upload or Publish
- **Ephemeral Transfers (`/s/<token>`):** Raw file bytes stored in a private Cloudflare R2 bucket (`fastshared`), accessed exclusively through short-lived signed URLs.
- **Web Publications (`p-<slug>.fastsha.red`):** Static web files (HTML, CSS, JS, images), PDF documents, or single files stored in a dedicated R2 bucket (`fastshared-publications`). Unpacked website files are served with strict Content Security Policy (CSP) headers and origin isolation.

### 3.2. File and Publication Metadata
Stored in our managed Neon Postgres database:
- Filename, file size in bytes, MIME content type, and SHA-256 content hashes.
- Publication slug, version numbers, entry path, and creation/expiration timestamps.
- Record of publication status (`active`, `expired`, `revoked`, `suspended`, `deleted`).

### 3.3. Authentication and Device Tokens
- **Apple Apps and CLI:** A cryptographically random device token generated locally on first launch and stored in the secure Apple Keychain or local CLI configuration. On the server, we store only a salted HMAC hash of the token to authenticate API calls.
- **Web Pro Users (Email Magic Link):** When you sign in or purchase Pro on the web, you provide your email address. We generate a single-use login token sent to your email. Upon verification, your browser receives a device bearer token saved strictly in browser `localStorage`. We do not set ambient cookies scoped to `.fastsha.red`.
- **Sign in with Apple (Optional):** If you choose to link devices or manage subscriptions via Sign in with Apple, we receive Apple’s stable pairwise subject identifier and, if shared by Apple, your private relay email and name.

### 3.4. Publication Open Beacon (Real-Browser Open Alerts)
To deliver the core feature of notifying authors when their deliverable is opened in a genuine web browser:
- When a client loads a publication page, a minimal client-side script transmits a verification beacon (`POST /opened` to the publication's own origin).
- **What is recorded:** A salted cryptographic hash (`visitor_hash`, generated from a client-side visitor ID and a secret server pepper) and the exact timestamp (`opened_at`).
- **Deduplication:** Multiple visits by the same visitor within a 24-hour window are recorded as a single open.
- **No Cross-Site Tracking:** The visitor identifier is scoped strictly to that individual publication origin (`p-<slug>.fastsha.red`). It cannot track the visitor across other publications or across the broader web.
- **No Link-Preview Triggers:** Preview unfurlers (Slack, WhatsApp, iMessage, Discord, Twitter bots) do not execute the required DOM script and do not trigger open alerts.
- **PDF Deliverables:** For inline PDF views where JavaScript is not executed, opens are recorded server-side using document request headers (`Sec-Fetch-Dest: document`) and hashed IP addresses, deduplicated per 24 hours.

### 3.5. Subscription and Payment Data
- **Web Purchases (Paddle):** Paddle.com acts as our Merchant of Record. FastShared receives and stores customer identifiers, transaction IDs, subscription status (`active`, `past_due`, `canceled`, `expired`), and billing period dates in an `entitlement` table. **FastShared never sees, processes, or stores your full credit card number, security code, or bank account details.**
- **Apple In-App Purchases:** Apple acts as merchant of record. We receive signed App Store transaction receipts and transaction identifiers via the App Store Server API.

### 3.6. Operational and Security Logs
Cloudflare processes standard HTTP request headers, including connecting IP address, requested path, HTTP status, and user-agent string, retained in rolling logs for up to 30 days to mitigate denial-of-service attacks, investigate abuse, and enforce tier rate limits.

---

## 4. Legal Bases for Processing (GDPR & LGPD)

We process your data under the following legal bases:
1. **Performance of a Contract (GDPR Art. 6(1)(b) / LGPD Art. 7(V)):** When you upload files, publish a project, or purchase FastShared Pro, processing your content, metadata, tokens, and billing status is necessary to deliver the requested service.
2. **Legitimate Interests (GDPR Art. 6(1)(f) / LGPD Art. 7(IX)):** Maintaining operational logs, enforcing rate limits, detecting fraud or malware, and calculating deduplicated publication opens represent our legitimate interests in operating a reliable, safe utility.
3. **Legal Compliance (GDPR Art. 6(1)(c) / LGPD Art. 7(II)):** Complying with statutory requests, addressing copyright notices, reporting CSAM to authorities, and maintaining financial audit trails.

---

## 5. Sub-processors and Third-Party Service Providers

We engage a minimal list of reputable infrastructure providers under strict Data Processing Agreements (DPAs) compliant with GDPR Article 28 and LGPD requirements:

| Sub-processor | Role and Activity | Data Location |
|---|---|---|
| **Cloudflare, Inc.** | Edge compute (Workers), object storage (R2), distributed key-value cache (KV), and web hosting (Pages). | Global edge network / United States |
| **Neon, Inc.** | Serverless Postgres database for application metadata, tokens, and publication records. | United States / AWS us-east-1 |
| **Apple Inc.** | App Store distribution, TestFlight, in-app purchases, and APNs push notifications for Apple apps. | United States / Global |
| **Paddle** (Paddle Payments Ltd / Paddle.com Inc / Paddle Technology Ltd) | Merchant of Record for web purchases, processing card and Pix payments, sales tax calculation, invoicing, and fraud protection. | United Kingdom / United States |
| **Transactional Email Provider** (e.g., Resend, Inc.) | Transmission of passwordless login magic links and publication expiration reminders. | United States |

We do not integrate advertising SDKs, third-party user tracking networks, Google Analytics, Facebook Pixel, or telemetry brokers.

---

## 6. Data Retention and Lifecycle

We practice rigorous data minimization:

### 6.1. Ephemeral File Transfers (`/s/<token>`)
- Links expire between 5 minutes and 30 days, as designated by the uploader.
- Once expired, links return HTTP 410 Gone immediately.
- The underlying object in Cloudflare R2 is permanently deleted within 24 hours after expiration. An R2 automated bucket lifecycle rule enforces hard deletion at 90 days as an immutable safety backstop.
- Non-content tombstone metadata (filename, size, timestamps) is preserved for 30 days to display deletion confirmation in user history, then pruned.

### 6.2. Web Publications (`p-<slug>.fastsha.red`)
- **Free Publications:** Expire automatically **7 calendar days** after publication. Files are permanently deleted from R2 within 24 hours of expiration.
- **Pro Publications:** Retained indefinitely for the duration of an active, paid Pro subscription.
- **Post-Cancellation / Grace Period:** When a Pro subscription is canceled or expires, publications enter a **30-day grace and notice window**. Owners are notified via email to export their deliverables. At the conclusion of 30 days, publications transition to expired and all associated files are permanently deleted.
- **Revocation:** If an author explicitly revokes a publication via CLI, web, or API, deletion of the storage prefix is scheduled immediately.

### 6.3. Accounts and Logs
- Inactive device token hashes are removed upon account deletion requests.
- Operational Cloudflare logs are purged on a rolling basis within 30 days.
- Financial entitlement and transaction references are retained for the statutory period required for tax, accounting, and dispute records.

---

## 7. International Data Transfers

FastShared is operated from Brazil, utilizing global cloud infrastructure provided by Cloudflare, Neon, Apple, and Paddle located primarily in the United States and the European Union/United Kingdom.

For users residing in the European Economic Area (EEA), United Kingdom, or Switzerland: transfers of personal data to sub-processors outside the EEA are governed by standard contractual clauses (SCCs) approved by the European Commission, the UK International Data Transfer Addendum, or relevant adequacy decisions.

---

## 8. Security Measures

We implement industry-standard technical and operational safeguards:
- **Transport Security:** All communications require TLS 1.3/1.2 with strict transport security.
- **Origin Isolation:** Each web publication is served on its own dedicated subdomain (`p-<slug>.fastsha.red`), preventing cross-origin script access, shared storage access, or cookie manipulation.
- **Hardened Sandbox Headers:** Publications are served with restrictive Content Security Policies (`sandbox allow-scripts allow-same-origin allow-popups allow-downloads; frame-ancestors 'none'`) with `allow-forms` strictly omitted to eliminate credential harvesting.
- **Secret Management:** Storage keys and tokens are stored encrypted or as salted cryptographic hashes (HMAC-SHA256).

---

## 9. Your Data Rights

Depending on your jurisdiction (under GDPR, LGPD, CCPA/CPRA), you have the right to:
1. **Access:** Request a summary and copy of personal data associated with your device token or email.
2. **Rectification:** Update or correct your email address or account details.
3. **Erasure ("Right to be Forgotten"):** Request immediate permanent deletion of all live uploads, publications, device tokens, and email records.
4. **Revocation & Self-Service Deletion:** Authors may revoke and trigger deletion of any upload or publication at any moment via the app, CLI (`fastshared publications revoke`), or API.
5. **Subscription Cancellation:** Cancel web recurring subscriptions at any time via the Paddle Customer Portal or in your account dashboard.
6. **Regulatory Complaints:** Lodge a complaint with your supervisory data protection authority (in Brazil, the ANPD — Autoridade Nacional de Proteção de Dados; in the EU, your national Data Protection Authority).

To exercise any of these rights, email us at `privacy@fastsha.red` referencing your account email or device identifier.

---

## 10. Children's Privacy

The Service is not directed to individuals under the age of 13 (or under 16 in certain EU member states). We do not knowingly collect personal data from children. If you become aware that a child has provided us with personal information or uploaded content without parental consent, please contact `privacy@fastsha.red` for immediate deletion.

---

## 11. Changes to this Privacy Policy

We may update this Privacy Policy from time to time to reflect product enhancements, legal requirements, or operational changes. All revisions will be dated at the top of this document. Material changes impacting data handling or retention will be notified via email to registered web users and announced inside the applications prior to taking effect.

---

## 12. Contact

For data protection questions, subject access requests, or privacy concerns:
- **Email:** `privacy@fastsha.red`
- **Postal Correspondence:** Matheus Kindrazki, Curitiba, PR, Brazil
