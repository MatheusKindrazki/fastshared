# DRAFT — requires founder/legal review

# Terms of Service — FastShared

> **Summary of changes vs current `web/src/pages/terms.astro` (v1.2, 24 April 2026):**
> 1. **FastShared Publications added:** Expands product scope from ephemeral raw file sharing (`/s/<token>`) to include interactive web publications (`https://p-<slug>.fastsha.red`), PDF presentations, and standalone files.
> 2. **Tier retention & lifecycle defined:** Free publications expire after 7 days (with up to 3 open alerts, 25 MB upload limit, 1 active publication, and mandatory footer badge). Pro publications remain active as long as the Pro subscription is active (2 GB total quota, 250 MB per upload, same-URL version updates, unlimited alerts, no footer badge).
> 3. **Cancellation & 30-day notice:** Explicitly defines the post-cancellation lifecycle: upon cancellation or non-renewal of Pro, publications enter a 30-day grace and notice window to allow export before irreversible permanent deletion.
> 4. **Paddle as Merchant of Record (Web Billing):** Adds required Paddle MoR disclosure ("Our order process is conducted by our online reseller Paddle.com..."), tax compliance, invoice handling, and web payment terms (Credit Cards, Apple Pay, and Pix).
> 5. **App Store purchases preserved:** Clarifies that in-app purchases on iOS and macOS remain sold through Apple Inc. as merchant of record, with App Store refund and subscription rules applying.
> 6. **Open notification beacon disclosed:** Explains that publications inject a browser open beacon to notify the owner upon real DOM rendering (collecting only a salted visitor hash and timestamp; no cross-site tracking, no third-party cookies).
> 7. **Prohibited content & anti-phishing:** Clarifies prohibition against credential-harvesting forms (enforced by disabling `allow-forms` in the Content Security Policy), malware, phishing, copyright infringement, and CSAM.
> 8. **Abuse reporting:** Formalizes abuse reporting via the `/v1/abuse-reports` endpoint, publication footer badges, and `support@fastsha.red`.
> 9. **Web authentication:** Defines the email magic link flow for web Pro accounts, using browser `localStorage` device tokens with no cross-domain cookies.

---

**Effective Date:** [Target: November 2026] · Version 2.0-draft  
**Operator:** Matheus Kindrazki (Individual Developer / Sole Operator, Curitiba, Paraná, Brazil)  
**Contact:** `support@fastsha.red` · `privacy@fastsha.red`

---

## 1. Acceptance of Terms

By downloading, installing, accessing, or using FastShared — including the iOS, iPadOS, and macOS applications, the command-line interface (`fastshared` CLI), the website at `fastsha.red`, the publication subdomains (`p-<slug>.fastsha.red`), the short-link service at `fastsha.red/s/<token>`, and any associated application programming interfaces (collectively, the "Service") — you agree to be bound by these Terms of Service ("Terms").

If you do not agree to these Terms, you must not access or use the Service. These Terms apply alongside our [Privacy Policy](/privacy/), our [Refund and Cancellation Policy](/refund-policy/), and any platform-specific terms that govern software distributed through Apple's App Store or transactions conducted via Paddle.

---

## 2. What the Service Provides

FastShared offers two primary modes of file sharing and publication:

1. **Ephemeral File Transfers (`/s/<token>`):** Quick, temporary uploads of files with configurable lifespans (from 5 minutes up to 30 days). Once the designated time window expires, the link returns HTTP 410 Gone and the underlying files are permanently deleted.
2. **Web Publications (`p-<slug>.fastsha.red`):** Direct publishing of interactive web deliverables (single-page sites, documentation, prototypes, Playwright/test reports, Plotly/Observable dashboards), PDF documents, and deliverables under unique, isolated subdomains, complete with real-time browser open alerts.

FastShared is not an archival storage service or perpetual backup repository. You are solely responsible for maintaining your own local copies and backups of all uploaded files and published materials.

---

## 3. Account, Authentication, and Identity

### 3.1. Device Tokens (Apple Apps & CLI)
Basic usage and anonymous publishing do not require traditional username/password accounts. Your device mints a private cryptographic token stored in secure system storage (such as the Apple Keychain access group or the CLI configuration file) to authenticate requests. Anyone with access to your device environment can use the Service under that token.

### 3.2. Web Accounts & Magic Links (Pro Web)
Subscribing to Pro via the web or managing publications across web browsers utilizes passwordless email magic link authentication (`POST /v1/auth/email/start`). Verifying the magic link issues a bearer token stored in your browser's `localStorage`. We do not set session cookies with domain-wide scope (`.fastsha.red`).

### 3.3. Sign in with Apple
On iOS and macOS, Sign in with Apple is available to link subscription entitlements and allowlists across your Apple devices under Apple's authentication framework.

### 3.4. Link Confidentiality
The URLs generated by FastShared (both `/s/<token>` and `p-<slug>.fastsha.red`) serve as bearer credentials. Anyone with access to the link may access or view the shared content unless additional access controls are configured. You are responsible for distributing your links only to intended recipients.

---

## 4. Subscriptions, Billing, and Merchant of Record

FastShared offers both a Free tier and a paid **FastShared Pro** tier (available as **Pro Monthly** and **Pro Annual** recurring subscriptions, and legacy **Pro Lifetime** one-time licenses).

### 4.1. Web Purchases via Paddle (Merchant of Record)
For purchases completed on the FastShared website (`web/pricing` or account management pages):

> **Our order process is conducted by our online reseller Paddle.com. Paddle.com is the Merchant of Record for all our orders. Paddle provides all customer service inquiries and handles returns.**

- When you purchase FastShared Pro via the web, your transaction is processed by Paddle.com (Paddle Payments Ltd / Paddle.com Inc.), which acts as the legal merchant of record. Paddle will appear on your credit card, bank, or Pix statement.
- Paddle is responsible for calculating, collecting, and remitting applicable sales taxes, value-added taxes (VAT/GST), and local levies across global jurisdictions.
- Web subscriptions renew automatically at the end of each billing cycle (monthly or annually) at the then-current standard rate, unless canceled prior to the renewal date via the Paddle Customer Portal or your FastShared account settings.
- For buyers in Brazil, Paddle supports **Pix** (including Pix Automático for subscriptions). Pix payments are subject to Brazilian tax (IOF) and require a valid CPF/CNPJ. Because Pix operates as deferred capture, Pro access is activated once Paddle confirms settlement via webhook.

### 4.2. In-App Purchases via Apple App Store
For purchases completed within the iOS or macOS applications:
- The transaction is conducted directly with Apple Inc. as the merchant of record under Apple’s standard Media Services Terms and Conditions.
- Auto-renewing subscriptions are managed and charged through your Apple ID account. You may manage or cancel auto-renewal at any time through **iOS Settings → Apple ID → Subscriptions** or **macOS App Store → Account Settings**.
- Cancellation must occur at least 24 hours prior to the end of the current billing cycle to prevent renewal charges by Apple.

### 4.3. Refunds
Refund policies differ based on your purchasing channel:
- **Web purchases (Paddle):** Governed by our [Refund and Cancellation Policy](/refund-policy/), offering a 14-day money-back guarantee for first-time subscriptions. Requests can be submitted to `support@fastsha.red` or via `paddle.net`.
- **Apple in-app purchases:** Refunds are handled exclusively by Apple according to App Store policies. FastShared cannot issue refunds directly for Apple transactions; please visit [reportaproblem.apple.com](https://reportaproblem.apple.com).

---

## 5. Publications: Tiers, Limits, and Lifecycle

### 5.1. Free Tier Limits
- **Active Publications:** Maximum of 1 active publication at any time.
- **Upload Size:** Maximum of 25 MB per upload.
- **Retention Period:** Publications expire automatically after **7 days** from creation.
- **Open Alerts:** Up to 3 real-browser open notification alerts per publication.
- **Attribution & Safety Badge:** Free publications automatically include a fixed, non-removable footer badge reading *"Hosted with FastShared · Report"* linking to abuse reporting.

### 5.2. Pro Tier Capabilities
- **Storage Quota:** Up to 2 GB total active storage across all publications.
- **Upload Size:** Up to 250 MB per individual upload.
- **Retention Period:** Publications remain active indefinitely for as long as your Pro subscription remains active and in good standing.
- **Same-URL Updates:** Ability to publish new versions under the same static publication URL (`p-<slug>.fastsha.red`).
- **Open Alerts:** Unlimited real-browser open notifications.
- **No Badge:** Removal of the FastShared attribution footer badge.

### 5.3. Cancellation and Post-Subscription Lifecycle
If your FastShared Pro subscription is canceled, fails to renew, or expires:
1. **30-Day Notice Window:** All existing publications remain online and accessible for a grace period of **30 calendar days** following the end of your paid billing period.
2. **Notification:** You will receive email notifications reminding you to export or download your publication contents before deletion.
3. **Permanent Deletion:** Upon the expiration of the 30-day notice window, publications transition to an expired status (returning HTTP 410 Gone) and all underlying files in object storage are permanently deleted within 24 hours. Deleted files cannot be recovered.

---

## 6. Open Notification Beacon

Publications hosted on FastShared automatically include a lightweight open-detection script:
- **Purpose:** To notify the publication owner (via push notification on Apple devices or CLI/API) when their client or recipient opens and renders the publication in a genuine web browser.
- **Data Processed:** The beacon transmits a cryptographically hashed visitor identifier (salted SHA-256) and a timestamp (`opened_at`) to record opens deduplicated per 24-hour window.
- **No Cross-Site Tracking:** The beacon operates strictly on the specific publication's isolated origin (`p-<slug>.fastsha.red`). It does not track users across external domains, does not read or set third-party advertising cookies, and ignores preview bots/link unfurlers (such as Slack, WhatsApp, iMessage, and Twitter bots).
- **PDF Deliverables:** For inline PDF views where JavaScript execution is not available, opens are recorded using server-side document request headers with IP hashing.

---

## 7. User Content and Intellectual Property

### 7.1. Ownership
You retain 100% ownership, copyright, and all intellectual property rights to the files, code, documents, and media you upload or publish through the Service.

### 7.2. Limited License to FastShared
By uploading content, you grant FastShared a non-exclusive, worldwide, royalty-free, limited license solely to store, process, unpack (in the case of ZIP archives for static sites), transmit, display, and serve the content to authorized recipients for the duration of your chosen retention period, and to delete the content upon expiration or revocation.

---

## 8. Prohibited Uses and Content Restrictions

You agree that you will not use the Service to upload, store, host, link to, or transmit any content or engage in any activity that:

1. **Child Sexual Abuse Material (CSAM):** Involves any depiction of child sexual abuse or exploitation. Any detected CSAM will be deleted immediately, the account/device permanently banned, and reported to the National Center for Missing & Exploited Children (NCMEC) and relevant law enforcement authorities.
2. **Malware and Exploits:** Contains viruses, trojans, worms, ransomware, keyloggers, spyware, or malicious code designed to harm, compromise, or disrupt recipient systems.
3. **Phishing and Credential Harvesting:** Imitates login portals, financial institutions, or authentic services to harvest credentials, session tokens, or personal information. FastShared strictly enforces sandbox isolation on publications (`Content-Security-Policy: sandbox allow-scripts allow-same-origin allow-popups allow-downloads; frame-ancestors 'none'`) with **no `allow-forms`**, blocking form submissions.
4. **Infringement:** Infringes upon any third party's copyright, patent, trademark, trade secret, or other proprietary rights.
5. **Harassment and Non-Consensual Imagery:** Contains non-consensual intimate imagery, doxxing material, hate speech, or content intended to harass, threaten, or defame individuals.
6. **Illegal Activity:** Violates any applicable municipal, state, federal, or international law, including the laws of the Federative Republic of Brazil and the user's jurisdiction.
7. **System Abuse:** Attempts to bypass storage caps, manipulate rate limits, perform denial-of-service attacks, reverse engineer the backend infrastructure, or tamper with the origin isolation of `fastsha.red`.

---

## 9. Abuse Reporting, DMCA, and Content Moderation

If we receive notice or become aware that an upload or publication violates these Terms:
- **Takedown:** We reserve the right to immediately revoke, suspend, or permanently delete the offending publication or link without prior notice.
- **Device & Account Banning:** We may invalidate associated device tokens, revoke entitlements, and ban associated email addresses.
- **Reporting Channels:** Abuse reports can be filed via:
  - The unauthenticated API endpoint: `POST https://api.fastsha.red/v1/abuse-reports`
  - The "Report" link embedded in the Free publication badge
  - Direct email to `support@fastsha.red`

For copyright infringement claims under the DMCA or applicable copyright legislation, notices should include identification of the copyrighted work, the specific publication URL, and claimant contact details.

---

## 10. Service Availability and Modifications

We strive to operate the Service with high reliability and low latency, but we do not guarantee continuous, error-free, or uninterrupted uptime. Service operations may be temporarily interrupted for scheduled maintenance, security updates, or emergency repairs, or due to outages at upstream sub-processors (Cloudflare, Neon, Apple, Paddle).

We reserve the right to modify, enhance, or discontinue features of the Service. When material changes are made to storage caps, pricing, or retention policies, active Pro subscribers will be provided with at least 30 days prior notice via email or in-app announcements.

---

## 11. Disclaimer of Warranties

THE SERVICE IS PROVIDED ON AN "AS IS" AND "AS AVAILABLE" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS, IMPLIED, STATUTORY, OR OTHERWISE, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, QUIET ENJOYMENT, OR NON-INFRINGEMENT.

WE DO NOT WARRANT THAT THE SERVICE WILL MEET YOUR REQUIREMENTS, THAT CONTENT SERVED THROUGH UNIQUE SUBDOMAINS WILL REMAIN IMMUNE TO THIRD-PARTY BLOCKING OR FIREWALL RESTRICTIONS, OR THAT DATA WILL NEVER BE LOST. YOU ARE SOLELY RESPONSIBLE FOR MAINTAINING INDEPENDENT BACKUPS.

---

## 12. Limitation of Liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL THE OPERATOR OF FASTSHARED (MATHEUS KINDRAZKI) OR OUR AFFILIATES, CONTRACTORS, OR SUPPLIERS BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF PROFITS, DATA, GOODWILL, REVENUE, OR WORK STOPPAGE, ARISING OUT OF OR IN CONNECTION WITH THE USE OF OR INABILITY TO USE THE SERVICE.

OUR TOTAL CUMULATIVE LIABILITY FOR ALL CLAIMS ARISING OUT OF OR RELATING TO THESE TERMS OR THE SERVICE SHALL NOT EXCEED THE GREATER OF:
(A) THE TOTAL AMOUNT PAID BY YOU TO FASTSHARED IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM; OR
(B) FIFTY BRAZILIAN REAIS (BRL 50.00).

SOME JURISDICTIONS DO NOT ALLOW CERTAIN LIMITATIONS OF LIABILITY; IN SUCH JURISDICTIONS, OUR LIABILITY IS LIMITED TO THE MINIMUM EXTENT PERMITTED BY LAW.

---

## 13. Indemnification

You agree to defend, indemnify, and hold harmless the operator of FastShared from and against any claims, liabilities, damages, losses, and reasonable legal expenses arising out of or in any way connected with: (a) content you upload, publish, or transmit; (b) your violation of these Terms; or (c) your violation of any rights of a third party.

---

## 14. Governing Law and Dispute Resolution

These Terms and any dispute arising from your use of the Service shall be governed by and construed in accordance with the laws of the **Federative Republic of Brazil**, without regard to conflict of law principles.

Any legal dispute that cannot be resolved amicably shall be submitted to the exclusive jurisdiction of the competent courts of the **City of Curitiba, State of Paraná, Brazil**, unless mandatory consumer protection regulations in your country of residence (such as within the European Union) grant you the statutory right to bring proceedings in your local domestic court.

---

## 15. Contact Information

For questions regarding these Terms, enterprise inquiries, or general support:
- **General Support & Billing:** `support@fastsha.red`
- **Privacy & Data Protection:** `privacy@fastsha.red`
- **Abuse Reports:** `support@fastsha.red` or `POST https://api.fastsha.red/v1/abuse-reports`
