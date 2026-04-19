# FastShared — ASO strategy

App Store Optimization plan for the 1.0 launch and the first two iteration
cycles. The goal is to rank for intent keywords (`share file`, `temporary
link`, `send file`) without competing on the burnt-out `file sharing` head
term dominated by WeTransfer and Dropbox.

Apple indexes **App name + subtitle + keyword field** as a flat bag. We do
not duplicate words across fields — doing so burns a slot.

---

## Keyword field — primary pack (commit for launch)

```
share,link,temporary,ephemeral,upload,transfer,file,expire,vanish,private,send,cloud,airdrop,clip
```

(97 / 100 chars, 14 keywords, no spaces.)

### Per-keyword reasoning

| keyword     | difficulty | volume  | rationale                                                                 |
| ----------- | ---------- | ------- | ------------------------------------------------------------------------- |
| `share`     | high       | high    | The core verb. Must appear once; app name carries it implicitly too.      |
| `link`      | medium     | high    | We produce links. Short, high-intent, reinforces the value prop.          |
| `temporary` | medium     | medium  | The strongest differentiator keyword against WeTransfer/Dropbox.          |
| `ephemeral` | low        | low-med | Technically loaded but growing among privacy-conscious searchers.         |
| `upload`    | high       | high    | Intent keyword — many people type "upload file" when they mean share.     |
| `transfer`  | medium     | medium  | Captures the WeTransfer migration funnel without naming them.             |
| `file`      | high       | high    | Breadcrumb; combinatorial with every other keyword (`share file`, etc.).  |
| `expire`    | low        | low-med | Differentiator alongside `temporary` and `vanish`. Cheap to own.          |
| `vanish`    | low        | low     | Brand-voice word from the hero tagline. Low volume but low competition.   |
| `private`   | medium     | medium  | Privacy-driven searcher funnel; pairs with app name (`private share`).    |
| `send`      | high       | high    | Alternate verb for `share` — catches the "send a file" long tail.         |
| `cloud`     | high       | high    | Comparison query ("cloud share", "cloud transfer"). Broad match.          |
| `airdrop`   | high       | high    | Apple-native comparison. We're "AirDrop for any link", not AirDrop.       |
| `clip`      | medium     | medium  | Clipboard + short-link association. Also surfaces against CloudApp/Droplr. |

### What we cut and why

- **`quick`, `fast`** — the app name already carries speed. Cutting these buys
  us one more differentiator keyword.
- **`wetransfer`, `dropbox`, `droplr`, `cloudapp`** — Apple rejects trademarked
  competitor names. Burning review velocity is not worth it.
- **`screenshot`, `photo`** — would be high-volume but divert us into the
  photo-sharing category (Photo & Video) where we don't belong.
- **`qr`, `barcode`** — we don't render QR codes today. Adding keywords for
  features we don't ship burns trust when the reviewer tries the obvious query
  and gets nothing.
- **`image`, `video`, `pdf`** — we support them but leading with specific file
  types narrows perceived scope. `file` covers it.

---

## Pro-launch pack (committed for v1.1)

```
share,link,temporary,ephemeral,upload,transfer,file,expire,private,airdrop,sync,subscription,icloud
```

(99 / 100)

### Per-keyword delta vs v1.0 pack

| keyword        | change   | rationale                                                              |
| -------------- | -------- | ---------------------------------------------------------------------- |
| `sync`         | added    | Pro iCloud sync is the core differentiator; also catches "photo sync". |
| `subscription` | added    | High-intent for people comparing subscription utilities.               |
| `icloud`       | added    | Apple-native match; pairs with `airdrop` for the ecosystem query.      |
| `vanish`       | removed  | Brand voice word; low volume, freed slot for Pro intent.               |
| `cloud`        | removed  | `icloud` is more specific and higher-intent for our audience.          |
| `send`         | removed  | `share` + `upload` + `transfer` already cover the intent space.        |
| `clip`         | removed  | Niche; Pro pack needs slots more than clipboard adjacency does.        |

`pro` was evaluated as a 14th keyword but the combined field would land at
103/100 characters. The app's name — "FastShared Pro" — already delivers the
`pro` token through the App name + subtitle index. Cutting it frees one slot
without losing the Pro-intent surface.

### Measurement

Hold for 7 days post v1.1 release before iterating. Compare installs-per-
impression vs v1.0 pack (which stays as the fallback if Pro pack
underperforms on conversion).

---

## Secondary packs (for A/B after we have 30 days of data)

These are equally-valid alternates. Change the keyword field (no re-submission
needed post-1.0) and observe installs-per-impression over a full week.

**Pack B — privacy-forward:**

```
share,link,temporary,ephemeral,private,secure,encrypted,expire,vanish,upload,send,transfer,token,clip
```

(100 / 100)

- Drops `cloud`, `file`, `airdrop`; adds `secure`, `encrypted`, `token`.
- Use if privacy channels (HN, BlueSky, r/privacy) are driving installs and we
  want to compound that intent.

**Pack C — apple-native-forward:**

```
share,link,temporary,airdrop,shortcut,siri,clipboard,upload,send,transfer,file,expire,vanish,private
```

(99 / 100)

- Drops `ephemeral`, `cloud`; adds `shortcut`, `siri`, `clipboard`.
- Use if the Shortcuts / Siri / Action Button story resonates in reviews and
  we want to double down on the "Apple-native utility" perception.

**Pack D — workflow-forward:**

```
share,link,temporary,upload,transfer,file,send,screenshot,recording,clip,paste,expire,vanish,private
```

(101 / 100 — trim `private` or `vanish` before shipping)

- Explicitly courts the workflow crowd (design, dev, support).

---

## Competitor keyword acknowledgements

We should know what each competitor "owns" so our own positioning does not
accidentally mirror theirs. We never copy their copy verbatim — we observe and
route around.

- **WeTransfer.** Owns `file transfer`, `send large files`, `big files`. We
  are deliberately smaller ("send any file, small, fast") — we cede
  large-file-transfer-as-a-service to them. Their "free plan" narrative is
  pay-walled after a download count; ours is "no account, ephemeral by
  design".
- **Dropbox Transfer.** Owns the Dropbox ecosystem play — send anything
  already in Dropbox. Comparison keyword for us is `cloud` plus `no accounts`.
  The absence of accounts is our biggest differentiator here.
- **Firefox Send (legacy).** The spiritual predecessor — encrypted, expiring
  file share. It got killed in 2020 and people still miss it. Our line is
  "Firefox Send on your phone, native." Do not use this in marketing copy
  directly but keep it as a talking point for HN/Reddit threads.
- **Droplr, CloudApp.** Both own the screenshot-share workflow for creative
  teams. They also both require accounts and subscriptions. Our line:
  "screenshot sharing without the account and without the monthly fee." We do
  not target their "annotation + comments" use case.
- **AirDrop.** Not a competitor in the App Store sense, but the most honest
  reference point Apple users have. Positioning: "AirDrop is for the room,
  FastShared is for everywhere else."

---

## Measurement plan

At D+7, D+14, D+30 after launch, pull from App Store Connect Analytics:

1. **Impressions by keyword** — confirm the primary pack keywords are actually
   surfacing us.
2. **Conversion rate per impression** — identify keywords that surface us but
   don't convert; those are the ones to cut in the next iteration.
3. **Search term queries that led to the page** — Apple exposes the top 25.
   Feed these back as candidate keywords for pack B/C/D.
4. **Ranking for "share file", "temporary link", "send file"** — these three
   are our north-star queries.

Every keyword field change requires a 7-day holding period before the next
one (to read signal clearly). Do not iterate faster than that.
