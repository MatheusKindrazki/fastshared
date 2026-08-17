# Email setup for `@fastsha.red` (Fastmail on Cloudflare DNS)

The site publishes four `@fastsha.red` addresses. **None of them can receive
mail today** — the domain has no MX records at all. This runbook makes them
work via Fastmail, which is already the chosen provider. It does not re-open
that decision, and it does not propose removing the published addresses.

Everything in section 1 was measured on 2026-08-17 and includes the commands to
re-measure it, because a runbook that asserts DNS state without showing how to
check it goes stale silently.

## Sources, and which one wins

DNS values in section 2 come from Fastmail's official documentation
(fastmail.help, "Setting up your domain: MX only"), read on 2026-08-17.

> **The Fastmail UI is the final authority.** Fastmail shows the exact records
> for *your* domain inside your own account. If its screen disagrees with this
> table, **the screen wins** and this file is wrong — fix this file. DNS values
> copied from third-party write-ups (or from a stale runbook like this one may
> become) are a classic cause of mail that silently never arrives.

The DKIM hostnames below are domain-specific: they embed `fastsha.red`. They
are correct for this domain only.

## 1. The problem

### Measured state — 2026-08-17

Queried against three independent resolvers (Cloudflare `1.1.1.1`, Google
`8.8.8.8`, Quad9 `9.9.9.9`). **All three agree**, which rules out one
resolver's stale cache as the explanation.

| Record | Measured value | Consequence |
| --- | --- | --- |
| `MX` for `fastsha.red` | **zero records** | No mail server is designated. Note the precise mechanism, because "no MX" does not mean senders give up immediately: under RFC 5321 §5.1 an absent MX makes the sender fall back to the **implicit MX**, i.e. the domain's `A`/`AAAA`. Those exist (see below) and point at Cloudflare's proxy, which does not answer on port 25 — so delivery still fails, but it fails by timing out or being refused at the edge rather than by "no such mail domain". Either way nothing arrives. |
| `TXT` with `v=spf1` | **zero records** | No SPF policy published. |
| `TXT` at `_dmarc` | **zero records** | No DMARC policy published. |
| Cloudflare Email Routing | **absent** | It would have installed `route1/2/3.mx.cloudflare.net` MX records; there are no MX records, so it is not enabled. |
| `TXT` at apex (existing) | `google-site-verification=QP01Al_TyhTD9W628Scebded18Vui2pRC1OdQkYkVBg` | Unrelated to mail, **but it must survive** the SPF change — see section 3. |
| Nameservers | `rayden.ns.cloudflare.com`, `elly.ns.cloudflare.com` | DNS is managed at Cloudflare; that is where the records get added. |
| Apex `A` / `AAAA` | `104.21.52.51`, `172.67.195.146`, `2606:4700:3035::6815:3433`, `2606:4700:3036::ac43:c392` | Cloudflare anycast addresses — the apex is **proxied** (orange cloud). Relevant because it sets the default habit that section 3 warns about. |

The four addresses are not "misconfigured", they are **unconfigured**. Mail
sent to them today fails; it is not sitting in a spam folder somewhere.

### Re-measure it yourself

```bash
for r in 1.1.1.1 8.8.8.8 9.9.9.9; do
  echo "=== resolver $r ==="
  echo "-- MX --";        dig +short MX   fastsha.red        @$r
  echo "-- TXT apex --";  dig +short TXT  fastsha.red        @$r
  echo "-- DMARC --";     dig +short TXT  _dmarc.fastsha.red @$r
  echo "-- NS --";        dig +short NS   fastsha.red        @$r
done
```

Empty output under `MX` and `DMARC` reproduces the broken state. Use three
resolvers here too: agreement across independent resolvers is what separates
"not published" from "published, and one cache hasn't caught up".

### What is published, and where

Confirmed by reading the files in this repo at the commit these paths point to.
Re-check with:

```bash
grep -rn "mailto:" web/src/pages/
```

| Address | Published at (`file:line`) | What it is |
| --- | --- | --- |
| `privacy@fastsha.red` | `web/src/pages/privacy.astro:37`, `:287`, `:372`; `web/src/pages/support.astro:82` | **The data-subject request route for LGPD / GDPR.** The privacy policy names it as the way to exercise those rights. A statutory request channel that bounces is a compliance problem, not an inconvenience. |
| `support@fastsha.red` | `web/src/pages/support.astro:27`; `web/src/pages/terms.astro:75`, `:326` | **The user support channel Apple requires**, and the one real users actually write to. Also see the escalation below. |
| `abuse@fastsha.red` | `web/src/pages/support.astro:59` | **The abuse channel for a file-sharing service.** Reports of illegal or infringing content arrive here. This is the most sensitive of the four: a file-sharing product whose abuse channel silently discards reports has no working path to act on them. |
| `press@fastsha.red` | `web/src/pages/press.astro:129` | Press kit contact. Lowest stakes of the four — a missed press email costs an opportunity, not a legal or safety obligation. |

Two notes where reality differs from how this is often summarized:

- `abuse@` is published in **`support.astro:59`**, not in `privacy.astro`.
- `privacy@` and `support@` each appear on **more than one page** (`support.astro`
  and `terms.astro` respectively), so the blast radius is wider than the
  "one address, one page" model suggests.

### Escalation: `support@` is also the App Review contact

```bash
grep -n "REVIEW_EMAIL" apple/.env.appstore.example
```

`apple/.env.appstore.example:12` sets `FASTSHARED_REVIEW_EMAIL=support@fastsha.red`,
and that file's own comment states these values **are sent to App Review**. So a
non-delivering `support@` is not only the user-facing support channel — it is
also the address Apple would use to reach the developer about a submission.
Fixing this is a release dependency, not only a website chore.

## 2. Records to add in Cloudflare

Literal values from Fastmail's official "MX only" documentation. Add them at
Cloudflare (the nameservers above confirm that is the authoritative place).

| Type | Name / Host | Value / Target | Priority | Proxy |
| --- | --- | --- | --- | --- |
| `MX` | `@` | `in1-smtp.messagingengine.com` | `10` | n/a |
| `MX` | `@` | `in2-smtp.messagingengine.com` | `20` | n/a |
| `TXT` | `@` | `v=spf1 include:spf.messagingengine.com ?all` | — | n/a |
| `CNAME` | `fm1._domainkey` | `fm1.fastsha.red.dkim.fmhosted.com` | — | **DNS only (grey)** |
| `CNAME` | `fm2._domainkey` | `fm2.fastsha.red.dkim.fmhosted.com` | — | **DNS only (grey)** |
| `CNAME` | `fm3._domainkey` | `fm3.fastsha.red.dkim.fmhosted.com` | — | **DNS only (grey)** |
| `TXT` | `_dmarc` | `v=DMARC1; p=none;` | — | n/a |

`MX` and `TXT` records are never proxied by Cloudflare — the grey/orange choice
only exists for `CNAME`/`A`/`AAAA`, which is why the Proxy column only matters
on the three DKIM rows.

I am deliberately not naming the specific buttons or tab labels in the
Cloudflare or Fastmail dashboards, because I have not verified their current
wording and UI labels change. Work in terms of the record operations above:
**add** these records, and leave the existing apex `TXT` alone.

### Why DKIM is not optional here

DKIM is required if you want DMARC to mean anything for this setup. By default
Fastmail uses its own domain in the return-path, so **SPF alignment does not
pass** for messages you send — DKIM is what carries the aligned identifier that
DMARC evaluates. Skipping the three DKIM `CNAME`s and then hardening DMARC is
how you end up failing DMARC on your own outbound mail.

## 3. Two Cloudflare-specific traps

### Trap 1 — the DKIM `CNAME`s must be grey (DNS only)

Cloudflare's proxy (orange cloud) answers with Cloudflare's own addresses
instead of resolving to the target. For a DKIM `CNAME` that breaks the lookup,
and **Fastmail cannot detect the record** — it reads as not set up.

This trap is live here specifically because the apex is already proxied (the
measured Cloudflare anycast IPs in section 1). Orange is the established habit
on this zone, and Cloudflare defaults new proxyable records to proxied. All
three `fm*._domainkey` records must be **DNS only / grey**.

### Trap 2 — do not destroy the existing apex `TXT`

The apex already has one `TXT` record:

```
google-site-verification=QP01Al_TyhTD9W628Scebded18Vui2pRC1OdQkYkVBg
```

Two rules, and confusing them is the usual way this breaks:

1. **Add a new `TXT` record for SPF. Do not edit the existing one.** Multiple
   distinct `TXT` records at the apex are normal and correct. The
   `google-site-verification` value and the SPF value belong in **two separate
   `TXT` records**. Editing the existing record's value in place — instead of
   creating a second record — is what silently drops the Google verification.
2. **Only one record may begin with `v=spf1`.** This constraint applies to SPF
   records specifically, not to `TXT` records in general. If a second mail or
   sending service ever needs SPF, do **not** add a second `v=spf1` record —
   combine its `include:` into the single existing SPF record (Fastmail's
   documentation notes a limit of 10 `include:` mechanisms). Two `v=spf1`
   records is a permanent SPF failure, not a fallback.

## 4. How to verify

DNS first, then real mail. **DNS looking correct is not proof of delivery** —
the only thing that proves the four addresses work is mail arriving in them.

### DNS checks and what "right" looks like

```bash
# MX — expect exactly these two, with these priorities
dig +short MX fastsha.red @1.1.1.1
#   10 in1-smtp.messagingengine.com.
#   20 in2-smtp.messagingengine.com.

# TXT apex — expect BOTH lines to be present (order is not significant)
dig +short TXT fastsha.red @1.1.1.1
#   "google-site-verification=QP01Al_TyhTD9W628Scebded18Vui2pRC1OdQkYkVBg"
#   "v=spf1 include:spf.messagingengine.com ?all"

# Exactly ONE record may start with v=spf1 — this must print 1, never 2
dig +short TXT fastsha.red @1.1.1.1 | grep -c "v=spf1"

# DKIM — each must return the CNAME TARGET, not a Cloudflare IP.
# A target here means grey/DNS-only. Cloudflare IPs (or an empty result plus
# A records) means the record is still proxied — that is Trap 1.
for n in fm1 fm2 fm3; do
  printf '%s: ' "$n"
  dig +short CNAME "$n._domainkey.fastsha.red" @1.1.1.1
done
#   fm1: fm1.fastsha.red.dkim.fmhosted.com.
#   fm2: fm2.fastsha.red.dkim.fmhosted.com.
#   fm3: fm3.fastsha.red.dkim.fmhosted.com.

# DMARC
dig +short TXT _dmarc.fastsha.red @1.1.1.1
#   "v=DMARC1; p=none;"
```

Re-run the MX and DMARC checks against `8.8.8.8` and `9.9.9.9` as well. Until
all three resolvers agree, you are looking at cache state, not at published
state.

**On timing:** I am not stating a propagation figure — I have not measured one
for this zone, and any specific number would be invented. Records become
visible as caches expire, bounded by the TTL on each record. Poll the commands
above rather than waiting a quoted interval.

### The check that actually matters

From an external mailbox (not a `@fastsha.red` address), send one message to
each of the four:

```
privacy@fastsha.red
support@fastsha.red
abuse@fastsha.red
press@fastsha.red
```

Confirm all four **arrive** in Fastmail. Test each one individually — they may
be configured as separate users, aliases, or a catch-all, and a working
`support@` proves nothing about `abuse@`. Also confirm no bounce message comes
back for any of them.

Then confirm Fastmail's own screen reports the domain as fully verified,
including DKIM. That screen is the authority on whether it can see the records.

## 5. Recommended order, and why

Do these in order. Each step is safe to leave in place before the next one
exists; the ordering exists so that no intermediate state is worse than the
current one.

1. **`MX` first.** This is the step that puts delivery on the right path, and
   the only one of the four that affects whether mail arrives at all.
   ⚠️ **DNS alone does not restore delivery, and this runbook cannot tell you
   when it does.** The `MX` records only hand the mail to Fastmail; Fastmail
   then has to be willing to accept it, which means the domain added and
   verified on their side and each of the four addresses existing there as a
   real mailbox or alias. Neither half works without the other, and only the
   second half is invisible to `dig`. Treat delivery as restored when a test
   message actually lands — see section 4 — not when the records resolve.
   Everything after this step is authentication and reputation: valuable, but
   nobody's privacy request is lost while you configure it.
2. **`SPF` (`v=spf1`) next.** Cheap, one record, and it is what receivers check
   first. Apply Trap 2 carefully here — this is the single step that can break
   something already working (the Google verification).
3. **`DKIM` (the three grey `CNAME`s) before hardening DMARC.** Not the other
   way around. Because SPF does not align for Fastmail's default return-path,
   DKIM is the identifier DMARC will pass on. Publishing a strict policy while
   DKIM is missing means your own outbound mail is what gets rejected.
4. **`DMARC` at `p=none` — and leave it there.** `p=none` is monitoring only:
   it asks for reporting without instructing receivers to act. Only consider
   `p=quarantine` and later `p=reject` after DKIM is verified in the Fastmail
   UI and real messages are observed passing. Jumping to `p=quarantine` or
   `p=reject` while authentication is incomplete does not block attackers, it
   blocks **your own email** — including the App Review contact from the
   escalation in section 1.

Do not skip step 4's staging just because steps 1–3 look correct in `dig`.
`p=none` costs nothing to keep and is the only state that lets you see failures
before receivers start enforcing them.

## Related, and explicitly out of scope

All four addresses render as links with `class="text-violet-hot"`. On the light
theme (the default), `--violet-hot` (`#9d7aff`) as text on the `--cream`
background measures **2.97:1**, which is below WCAG AA — one of 10 measured
occurrences of that open defect. Fixing DNS does not affect it, and it is not
part of this runbook. Noted only so it is not mistaken for something this
change addressed.
