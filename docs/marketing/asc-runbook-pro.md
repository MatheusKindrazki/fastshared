# FastShared Pro — App Store Connect runbook

Manual runbook for configuring FastShared Pro in App Store Connect. Each
step ends in an acceptance signal. Do NOT skip acceptance.

**Plan reference:** `docs/plan/pro-feature-C-launch.md`, Part 7.

**Related plans (executed in parallel):**

- Plan A (backend) — builds `/v1/iap/webhook`, StoreKit server verification,
  tier cap enforcement, `subscriptions` table in Neon Postgres.
- Plan B (Apple) — builds StoreKit 2 product fetch, paywall UI, receipt
  submit, CloudKit metadata sync.

**The webhook URL and product IDs in this runbook are contract-locked to
Plan A + Plan B. Do not change them.**

---

## Pre-flight

Before starting Task C7.1, verify:

- [ ] Paid Apps Agreement is active in App Store Connect → Agreements,
      Tax, and Banking.
- [ ] Tax forms filled out and signed.
- [ ] Banking details saved.
- [ ] Your ASC role is **Admin** or **App Manager** for FastShared.

If any of these is missing, STOP — the rest of the runbook will not be
possible.

---

## C7.1 — Create Subscription Group "FastShared Pro"

**ASC screen:** My Apps → FastShared → Monetization → Subscriptions →
`+` (Create Subscription Group).

**Steps:**

1. Reference Name: `FastShared Pro`
2. Save.
3. In the new group, add localisations:
   - English (U.S.): Display Name `FastShared Pro`, App Name `FastShared`.
4. Save.

**Acceptance:** Subscription group appears in the list as `FastShared Pro`.
Screenshot saved to `/tmp/asc-C7.1.png`.

---

## C7.2 — Create IAP product `.pro.monthly`

**ASC screen:** Subscription group "FastShared Pro" → `+ Add` →
Auto-Renewable Subscription.

**Steps:**

1. Reference Name: `Pro Monthly`.
2. Product ID: `red.fastsha.pro.monthly`
   (Reverse-DNS bundle-prefix must match what the Apple client uses when
   calling `Product.products(for:)`.)
3. Subscription Duration: **1 Month**.
4. Subscription group: already set to `FastShared Pro`.
5. Price: USD **$2.99**. Click "Apply to All Territories" → Auto-managed
   pricing ON.
6. Localisations (English):
   - Display Name: `FastShared Pro Monthly`
   - Description: `Unlimited uploads, 2 GB files, 30-day links, iCloud history sync.`
7. Review Screenshot: 1290x2796 pixel IAP screenshot (iPhone 6.9 inch). Upload
   placeholder for now; final screenshot created in C7.8.
8. Review Notes:
   > Pro Monthly unlocks unlimited uploads per day, 2 GB max file size,
   > 30-day link retention, and cross-device history sync via iCloud
   > CloudKit private database.
9. Family Sharing: **OFF**.
10. Save.

**Acceptance:** Product status is "Missing Metadata" or "Ready to Submit".
Screenshot saved.

---

## C7.3 — Create IAP product `.pro.annual`

**ASC screen:** Subscription group "FastShared Pro" → `+ Add` →
Auto-Renewable Subscription.

**Steps:**

1. Reference Name: `Pro Annual`.
2. Product ID: `red.fastsha.pro.annual`
3. Subscription Duration: **1 Year**.
4. Price: USD **$19.99**. Auto-managed pricing ON. All territories.
5. Localisations (English):
   - Display Name: `FastShared Pro Annual`
   - Description: `Unlimited uploads, 2 GB files, 30-day links, iCloud sync. Save about 44% vs monthly.`
6. Review Screenshot: 1290x2796 — placeholder then final in C7.8.
7. Review Notes:
   > Pro Annual unlocks unlimited uploads per day, 2 GB max file size,
   > 30-day link retention, iCloud cross-device sync, priority support.
   > Billed once per year.
8. Family Sharing: **OFF**.
9. Save.

**Acceptance:** Product appears in subscription group next to Monthly.
Screenshot saved.

---

## C7.4 — Create IAP product `.pro.lifetime` (Non-Consumable)

**ASC screen:** My Apps → FastShared → Monetization → In-App Purchases →
`+` (New) → **Non-Consumable** (NOT a subscription).

**Steps:**

1. Reference Name: `Pro Lifetime`.
2. Product ID: `red.fastsha.pro.lifetime`
3. Price: USD **$49.99** (Early Access pricing). Auto-managed pricing ON.
   All territories.
4. Localisations (English):
   - Display Name: `FastShared Pro Lifetime`
   - Description: `Buy Pro once. Unlimited uploads, 2 GB files, 30-day links, iCloud sync, Family Sharing included.`
5. Review Screenshot: 1290x2796 — placeholder then final in C7.8.
6. Review Notes:
   > Pro Lifetime is a one-time purchase unlocking all Pro features
   > forever (unlimited uploads, 2 GB files, 30-day retention, iCloud
   > sync, priority support). Family Sharing supports up to 6 family
   > members.
7. Family Sharing: **ON**.
8. Save.

**Acceptance:** Lifetime product appears under In-App Purchases (separate
from subscription group). Screenshot saved.

---

## C7.5 — Configure Server-to-Server Notifications v2

**ASC screen:** My Apps → FastShared → App Information → scroll to
**App Store Server Notifications**.

**Steps:**

1. Notification Version: **Version 2**.
2. Production Server URL: `https://fastsha.red/v1/iap/webhook`
3. Production Server URL Version: 2
4. Sandbox Server URL: `https://fastsha.red/v1/iap/webhook`
   (Same URL. Plan A's webhook handler differentiates sandbox vs production
   by the notification payload's `environment` field.)
5. Sandbox Server URL Version: 2
6. Save.

**Acceptance:** Both URLs are saved. Click "Send Test Notification" if
available; Plan A's webhook should log the receipt. If Plan A is not yet
deployed, log the URL and defer the test to Plan A's completion.

**If Task Fails:**

- URL rejected as invalid: the webhook must return 200 OK on a test POST.
  Wait for Plan A to deploy the `/v1/iap/webhook` route, then retry.
- Don't configure a different URL. It is contract-locked to Plan A.

---

## C7.6 — Generate App Store Connect API key for StoreKit Server API

**ASC screen:** Users and Access → Integrations → **App Store Connect API**
→ Keys → `+` (Generate API Key).

**Steps:**

1. Name: `fastshared-iap-server-v1`
2. Access: **App Manager** (minimum role needed to query purchases; DO NOT
   give Admin).
3. Click **Generate**.
4. Download the `.p8` file ONCE — Apple does not let you download it
   again. Store it in the password manager immediately.
5. Copy the **Key ID** (format: 10 chars, e.g., `A1B2C3D4E5`). Save it.
6. Copy the **Issuer ID** (UUID at the top of the Keys page). Save it.

**Acceptance:** `.p8` saved to password manager; Key ID + Issuer ID
written down.

---

## C7.7 — Store the .p8 + IDs as Wrangler secrets

**Prerequisites:** C7.6 complete. Plan A's Worker project exists at
`backend/`.

**Steps:**

1. Base64-encode the .p8 file (Cloudflare Workers cannot handle multi-line
   secrets directly):

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
   # Expected: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID,
   # APP_STORE_CONNECT_KEY_P8_B64 present
   ```

4. Shred the local copy of `/tmp/p8.b64`:

   ```bash
   shred -u /tmp/p8.b64 2>/dev/null || rm -P /tmp/p8.b64
   ```

**Acceptance:** `wrangler secret list` shows the three keys; local temp
copy deleted.

**If Task Fails:**

- `wrangler: command not found` → `pnpm install -g wrangler` (or run
  `pnpm dlx wrangler …`).
- Secret rejected (too large): the base64 of a p8 is ~340 bytes — well
  within the 1024-byte secret cap. If rejected, re-check the base64 is
  single-line (`base64 -i file.p8 | tr -d '\n'`).

---

## C7.8 — IAP screenshots + review copy finalisation

**ASC screen:** Each IAP's detail page → Review Information → upload
screenshot.

**Steps:**

1. Generate screenshots automatically:

   ```bash
   cd /Users/matheuskindrazki/development/crazy-ideas/fastshared
   make appstore-screenshots
   ```

2. Use the generated Pro paywall review screenshot:
   `apple/fastlane/screenshots/iap/en-US/01_APP_IPHONE_67_iap-pro-review.png`.
3. Upload the generated screenshot to each IAP if App Store Connect still
   requires the per-product Review Information field.
4. Re-review localised Display Name + Description (already filled in C7.2
   / C7.3 / C7.4 — verify accuracy).
5. Save each IAP.

**Acceptance:** Every IAP status transitions from "Missing Metadata" to
"Ready to Submit" or equivalent. Each has a screenshot. Screenshot saved
of the IAP list.

**If Task Fails:**

- Screenshot rejected (wrong size): iPhone 6.9 inch spec includes 1290x2796. Use 1242x2688 only as a fallback if App Store Connect accepts the older 6.5 inch display set. Confirm current Apple spec on
  <https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/>.

---

## C7.9 — Configure Tax Category and App Privacy

**ASC screen:** My Apps → FastShared → App Information → Tax Category.

**Steps:**

1. Tax Category: **Software Utility** (confirm with accountant; this
   affects how Apple withholds tax). Save.
2. Publish App Privacy from the repo:

   ```bash
   cd /Users/matheuskindrazki/development/crazy-ideas/fastshared
   make appstore-privacy
   ```

   The source of truth is `apple/fastlane/app_privacy_details.json`, aligned
   with `docs/ops/appstore-launch-setup.md`.

**Acceptance:** App Privacy product-page preview matches
`docs/ops/appstore-launch-setup.md`. ATT confirmation remains "Not
Required".

---

## C7.10 — Create App Review sandbox tester account

**ASC screen:** Users and Access → Sandbox → Testers → `+`.

**Steps:**

1. Create a sandbox tester:
   - First/Last: `FastShared Review`
   - Email: `sandbox-review+v1@fastsha.red` (use `+` aliasing on your
     domain via Fastmail).
   - Password: strong, stored in password manager.
   - App Store Territory: United States.
2. Save.
3. Share credentials with Apple App Review via the submission's Review
   Information → Sign-In Info → Demo Account (only if Apple asks;
   FastShared doesn't require sign-in, so typically N/A, but Pro reviewers
   may need a sandbox Apple ID to test purchases).

**Acceptance:** Sandbox tester appears in the list. Credentials stored.

---

## C7.11 — Pre-submission check

**Read-only verification — tick every row:**

- [ ] 3 IAPs created with exact Product IDs:
      `red.fastsha.pro.monthly`,
      `red.fastsha.pro.annual`,
      `red.fastsha.pro.lifetime`.
- [ ] Subscription group `FastShared Pro` contains Monthly + Annual.
- [ ] Lifetime is a Non-Consumable IAP outside the subscription group.
- [ ] Prices: $2.99 / $19.99 / $49.99 USD, auto-managed on.
- [ ] Family Sharing: OFF on Monthly + Annual, ON on Lifetime.
- [ ] S2S notification URL set for both Production and Sandbox.
- [ ] ASC API key generated, .p8 + Key ID + Issuer ID stored as Wrangler
      secrets.
- [ ] IAP screenshots uploaded.
- [ ] Tax category set. App Privacy matches `docs/ops/appstore-launch-setup.md`.
- [ ] Sandbox tester created.

**Acceptance:** Every row ticked. Proceed to launch sequencing in
`docs/marketing/launch-sequence-pro.md`.

---

## Failure recovery

- **ASC misconfiguration:** most ASC fields are editable without
  resubmission, EXCEPT Product ID (permanent). If a Product ID is wrong,
  the product must be marked "Removed from sale" and recreated with the
  correct ID — this is costly and blocks Plan B.
- **Wrangler secret leak:** rotate the ASC API key via Users and Access →
  Integrations → Revoke, then generate a new one and re-run C7.6 + C7.7.
  Audit backend logs for any use of the leaked key.
