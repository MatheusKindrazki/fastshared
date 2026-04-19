# FastShared — voice and tone

How FastShared sounds in text, everywhere. One page so the whole team
internalises it.

---

## Voice — three adjectives

**Confident.** The product knows exactly what it is (a temporary share
utility) and exactly what it isn't (a cloud drive). We write like that. No
hedging, no "could", no "maybe".

> _Yes_ — "Every link expires."
> _No_ — "Most links will expire after a configurable window."

**Minimal.** Short sentences. Few adjectives. One idea per line. If a word
isn't carrying weight, it goes.

> _Yes_ — "Share anything. Get a link."
> _No_ — "Easily share any of your important files and instantly receive a
> convenient shareable link."

**Poetic.** The product is about time — things appearing, things
disappearing. The copy earns one metaphor per screen, no more. "Watch it
vanish." "Watch your upload breathe." One per moment.

> _Yes_ — "By design."
> _No_ — "Because we prioritize your privacy above all else."

---

## Tone shifts by surface

| Surface                      | Tone                                                                                                   |
| ---------------------------- | ------------------------------------------------------------------------------------------------------ |
| App UI — neutral states      | Quiet, confident. State the fact. "Link expires in 23h 59m."                                           |
| App UI — empty states        | Poetic, one beat. "Nothing here yet. Share a file to start the countdown."                             |
| App UI — errors              | Direct, blameless. No `:(`, no "oops". "The upload couldn't finish. Check your connection and retry." |
| App UI — destructive actions | Declarative, not scary. "Revoke link" — not "Permanently and irrecoverably destroy this link forever". |
| Marketing headlines          | Poetic. Three short beats. "Share anything. Get a link. Watch it vanish."                              |
| Marketing body               | Confident and minimal. Facts with a trace of the concept behind them.                                  |
| Technical docs               | Plain, useful, specific. Numbers over adjectives. "Default retention is 24 h. Custom 300 s–30 d."      |
| Release notes                | Conversational but still terse. Lead with what changed, not why.                                       |
| Legal                        | Plain English. Legally sufficient, not lawyer-styled. "You own what you upload."                       |

---

## Do / don't — with real strings from the product

### Do — 5 examples

1. **"Share anything. Get a link. Watch it vanish."** _(landing hero)_ — three
   beats, ending on the differentiator.
2. **"Every link expires. Every file is deleted. By design."** _(landing)_ —
   declares the constraint as a feature.
3. **"Link expires in \<time\>. Media is deleted 24 hours later."** _(share
   extension confirmation)_ — one fact, one fact, that's it.
4. **"Stage a temporary link."** _(share extension header)_ — uses "stage"
   because it's precise: the link exists before the upload finishes.
5. **"Watch uploads breathe in the Dynamic Island."** _(landing)_ — one
   metaphor, earned, supported by the visual below it.

### Don't — 5 examples

1. **"FastShared revolutionizes file sharing for the modern era."** — every
   word is bloat. "Revolutionizes" is the tell.
2. **"Oops! Something went wrong."** — blame-free is good, cute is bad.
   _Instead_ → "The upload couldn't finish."
3. **"Unlock the power of ephemeral sharing today."** — "unlock the power"
   is marketing residue. The product doesn't say "unlock"; the product
   shares.
4. **"Our industry-leading security protects your data."** — self-ranking
   claims are always weak. _Instead_ → "Private bucket. Signed reads.
   60-second TTL. No exceptions."
5. **"Share files easily and quickly with FastShared!"** — the exclamation
   mark, the adverb stack, and the product-name-at-the-end construction all
   fail the voice test at once.

---

## Word list — prefer vs avoid

| prefer                              | avoid                                                |
| ----------------------------------- | ---------------------------------------------------- |
| temporary                           | disposable, self-destructing                         |
| expires                             | self-destructs, kills itself                         |
| vanish (brand-voice, 1× per screen) | disappear, poof, gone (when precision matters)       |
| ephemeral (once per page)           | ephemeral (twice per page — it gets precious)        |
| deleted                             | removed (too soft), wiped (too violent), erased      |
| link                                | URL (in UI), hyperlink                               |
| native                              | best-in-class, world-class, premium                  |
| Apple-native                        | cross-platform (we aren't)                           |
| private                             | secure (we don't claim unconditional "secure")       |
| Mac / iPhone / iPad                 | device, handset, smartphone                          |
| 24 hours / 24 h                     | one day (ambiguous vs "a day")                       |
| revoke                              | cancel (overloaded), delete the link (already deleted) |
| no account                          | accountless (not a word we want to own)              |
| by design                           | on purpose (good for speech; stilted in marketing)   |
| countdown                           | timer (countdown has direction)                      |
| recipient                           | receiver, viewer, guest                              |
| the link is the credential         | use your link as a password (confusing)              |

---

## Punctuation rules

- **Em dashes.** Allowed, unspaced, to join two clauses where a colon would
  feel heavy. `Share anything — get a link — watch it vanish` is fine for
  social; the landing hero uses periods for more weight.
- **Exclamation marks.** Never. Not in error messages, not in marketing, not
  even in welcome screens.
- **Ellipses.** Never decorative. Only when actually truncating
  (`fastsha.red/s/abc…`).
- **Curly quotes.** In marketing and legal, yes. In code blocks and mono
  monospace, straight quotes.
- **Oxford comma.** Yes.
- **Numbers.** Spell out zero to nine. Numerals for ten and above. Always use
  numerals in UI when space is tight (`5 min`, `24 h`, `30 d`).
- **Time.** `24 h`, `30 d`, `5 min` in UI. `24 hours`, `30 days`, `5 minutes`
  in long-form copy.
- **Capitalisation.** Sentence case for headings. Title Case only for the
  wordmark (`fastshared`, lowercase — the wordmark is already final).

---

## Brand-speak cheat sheet

The product name is **FastShared**. One word. Capital F, capital S. _Not_
`FastShare`, `Fast Shared`, `fast-shared`. The wordmark in design is lowercase
(`fastshared`) — the typeset form — but in copy we use `FastShared`.

The domain is **fastsha.red** for the landing page and **fsh.re** for
generated short links. Both are intentional; do not "fix" either.
