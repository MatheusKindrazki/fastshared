# FastShared Apple — Friendly Design System (MASTER)

This file is the single source of truth for design decisions on the FastShared iOS, iPadOS, and macOS app surfaces (`apple/`). All `/ui-ux-pro-max`, `/impeccable`, and SwiftUI design work loads this before doing any work.

**Sister scope (do not cross-apply):** the marketing site at `web/` runs on a different aesthetic locked in `web/.impeccable.md` (dark-only, ephemeral · opinionated · crafted). Friendly applies only to native app surfaces.

Last updated: 2026-04-26

---

## Design Direction

**Friendly Redesign.** Light-first, warm, human-centered, soft and spacious. Pivots away from the previous warm-amber-on-dark direction. Communicates "ephemeral sharing as everyday kindness" rather than "ephemeral link as technology."

Brand DNA preserved from the previous redesign:
- Raster paper-plane mark with violet flight arc and optional ambient halo
- Bricolage Grotesque (display) + JetBrains Mono (mono)
- Ephemerality as the core gesture (countdown, urgency, decay)

What changed:
- Light theme is primary; dark is first-class secondary
- Cream ground (`#fbf8f1`) replaces dark ink (`#070318`) as the marketing/onboarding canvas
- Urgency communicated via tinted backgrounds + dots, not coral side-stripes
- Emoji file glyphs replace abstract icons in file tiles
- Soft shadows + soft minimum radius (10px) replace sharp edges + glow

---

## Tokens (Single Source of Truth)

**Decision: tokens consolidate into `Packages/FastSharedCore/Sources/FastSharedCore/Branding/BrandPalette.swift` as a public `enum FriendlyPalette { … }`.** The `apple/FastSharedApp/Components/BrandPalette+Redesign.swift` extension and the inline `FriendlyTokens` in `apple/FastSharedShareExt/ShareRootView.swift:13-40` collapse to thin shims that import from Core. This eliminates 3-way drift across app + share-ext + widget targets.

### Color — light theme (primary)

| Token | Value | Usage |
|---|---|---|
| `ground` | `#fbf8f1` | App background |
| `canvas` | `#ffffff` | Section backgrounds, scrollable surfaces |
| `surface0` | `#f5f1e6` | Subtle elevation under cards |
| `surface1` | `#eae4d4` | Pressed/secondary state |
| `paper` | `#ffffff` | Cards, sheets |
| `line` | `rgba(33,18,68,0.08)` | Hairline dividers |
| `lineStrong` | `rgba(33,18,68,0.16)` | Emphasized borders |
| `text` | `#1a0f38` | Primary text |
| `textDim` | `rgba(26,15,56,0.64)` | Secondary text |
| `textFaint` | `rgba(26,15,56,0.40)` | Tertiary / metadata |
| `shadow` | `0 2px 8px rgba(33,18,68,0.06), 0 8px 24px rgba(33,18,68,0.04)` | Card resting elevation |
| `shadowLg` | `0 4px 16px rgba(33,18,68,0.08), 0 16px 48px rgba(33,18,68,0.06)` | Sheets, modals |

### Color — dark theme (first-class secondary)

| Token | Value | Usage |
|---|---|---|
| `ground` | `#0d0625` | App background |
| `canvas` | `#140a38` | Section backgrounds |
| `surface0` | `#1a0f4a` | Cards |
| `surface1` | `#281664` | Pressed state |
| `paper` | `#1a0f4a` | Cards, sheets |
| `line` | `rgba(255,255,255,0.09)` | Hairline dividers |
| `lineStrong` | `rgba(255,255,255,0.18)` | Emphasized borders |
| `text` | `#f7f4ff` | Primary text |
| `textDim` | `rgba(247,244,255,0.66)` | Secondary text |
| `textFaint` | `rgba(247,244,255,0.38)` | Tertiary / metadata |

### Color — accents (theme-independent)

| Token | Value | Usage |
|---|---|---|
| `accentHot` | `#ff9f47` (amber) | Primary CTA, focus rings |
| `accentSoft` | `#ffc487` | Hover, secondary |
| `accentFade` | `#ff4e7c` (coral) | "Ending" semantics, gradients |
| `accentDust` | `#ffe0b8` | Particle, halo |
| `successGreen` | `#22c27a` | Success states |

### Color — urgency 4-tier (theme-aware backgrounds)

Urgency is the central design grammar of FastShared. Replaces the old coral side-stripe pattern. Every link row, countdown, and Live Activity surface uses one of these tiers based on remaining time.

| Tier | Text | Light bg | Dark bg | When |
|---|---|---|---|---|
| `critical` | `#ff4e7c` | `#fff0f4` | `#3d0f22` | < 1 hour remaining |
| `warning` | `#ff9f47` | `#fff5e8` | `#3d2410` | < 6 hours remaining |
| `normal` | `#9d7aff` | `#f3eeff` | `#2a1a5e` | < 24 hours remaining |
| `calm` | `#6b5fb8` | `#ece8f7` | `#1f1847` | > 24 hours remaining |

`apple/FastSharedApp/Components/ExpiryTier.swift` already maps this. Do not duplicate the mapping.

### Typography

Same fonts as the previous direction; scale shifted larger.

- **Display:** Bricolage Grotesque (700 / 600 weights primarily). Stylistic alternates `ss02 cv11 ss01` enabled.
- **Mono:** JetBrains Mono (600 / regular). Reserved for links, codes, countdown numerals (with `tabular-nums` enabled), uppercase labels.

**Type scale** (use exact values, not approximations):

| Role | Size | Weight | Tracking | Line-height |
|---|---|---|---|---|
| Hero (Onboarding, Empty) | 32px | 700 | -0.03em | 1.1 |
| Hub greeting | 28px | 700 | -0.025em | 1.15 |
| Detail filename | 17px | 700 | -0.015em | 1.3 |
| Section header | 15px | 700 | -0.01em | 1.4 |
| Body primary | 15px | 400/600 | 0 | 1.5 |
| Body secondary | 14px | 500/600 | 0 | 1.5 |
| Caption / metadata | 12px | 600 | 0 (or 0.05em uppercase) | 1.4 |
| Hint / faint | 11px | 600 | 0.05em uppercase | 1.4 |
| Countdown hero | 56px | 700 | -0.04em | 0.9 (`tabular-nums`) |
| Countdown inline | 22px | 700 | -0.03em | 1.0 (`tabular-nums`) |

**No third typeface.** Do not introduce a serif "for warmth" or a script "for friendliness." Friendly comes from spacing, color, and copy — not type variety.

### Spacing scale

| Token | Value |
|---|---|
| `xs` | 6 pt |
| `sm` | 10 pt |
| `md` | 16 pt |
| `lg` | 24 pt |
| `xl` | 32 pt |
| `xxl` | 48 pt |

### Radius scale

| Token | Value | Usage |
|---|---|---|
| `sm` | 10 pt | Small tiles, icon containers |
| `md` | 14 pt | Buttons, list rows |
| `lg` | 20 pt | Cards, grouped sections |
| `xl` | 28 pt | Countdown hero container, sheets |
| `pill` | 999 pt | Toggles, badges |

**Soft minimum 10pt — never sharp corners.** Even hairline dividers can wrap rounded surfaces.

### Motion

- Spring curve: `cubic-bezier(0.16, 1, 0.3, 1)` (`Animation.spring(response: 0.45, dampingFraction: 0.85)` in SwiftUI)
- Hover/tap transitions: 200–250ms
- Countdown ring: SVG `strokeDashoffset` animated; 60fps
- Reduced motion (`UIAccessibility.isReduceMotionEnabled`): freeze countdown at current state, disable plane fly-in (mark stays static), disable ring sweep

---

## Voice

Conversational, second-person, action-focused. Numbers and times are factual and precise. No hype, no jargon, no "AI-era" tropes.

**Reference copy** (verbatim from Friendly canvas — match this register):

- "Share files that don't stick around."
- "Fast, temporary links. No accounts, no clutter."
- "4 links live right now"
- "One expires in under an hour — tap to extend or stop sharing."
- "Ready when you are."
- "Try the share sheet in Photos — pick FastShared."
- "Link copied!"
- "Paste it anywhere. It expires in 24 hours."
- "Stop sharing now"
- "Extend expiration"

---

## File Representation

Use **emoji glyphs** in 44pt tiles, not abstract icons.

| File type | Glyph |
|---|---|
| Image | 🖼 |
| Video | 🎬 |
| PDF / Document | 📄 |
| Audio | 🎵 |
| Archive | 📦 |
| Code | 💾 |
| Unknown | 🔗 |

The tile background uses the urgency tier's light background color (`tier.bgLight` / `tier.bgDark`). The glyph itself is rendered at SF Symbol size 22pt centered.

---

## Design Principles

These five rules must pass for every change in `apple/`. If a proposed change violates one, it doesn't ship without an explicit override.

1. **Friendly comes from spacing, not from style decoration.** Generous whitespace + soft radii + emoji glyphs do the work. Don't add gradients, glows, or "fun" embellishments. The warmth is in restraint.

2. **Urgency is the central grammar.** Every surface that shows a link uses an urgency tier (critical/warning/normal/calm) for color + background + dot. Same information whether on the Hub row, Detail hero, Live Activity, or Lock Screen. Never invent a one-off "just for this view."

3. **Light is primary, dark is first-class.** Both themes ship; both must be tested every visual change. Don't tune one and assume the other. `@Environment(\.colorScheme)` is the only branching mechanism — no platform-specific theme overrides.

4. **Three typographic registers, no more.** Display Bricolage for headlines and answers, Mono JetBrains for labels/numbers/links, dim/faint variants for hierarchy. No serif, no script, no third weight system.

5. **One token source.** All colors, spacing, radius, and shadow values come from `FastSharedCore.FriendlyPalette`. The app target, share extension, and Live Activity widget all import from there. No inline copies, no per-target redefinitions, no "I'll just hardcode this one value."

---

## Decisions Locked (do not re-open without explicit ask)

These were resolved 2026-04-19 during `/ui-ux-pro-max` teach. Re-opening requires an explicit user override.

1. **Token source of truth:** `FastSharedCore.FriendlyPalette` (public enum). The current `apple/FastSharedApp/Components/BrandPalette+Redesign.swift` and `apple/FastSharedShareExt/ShareRootView.swift:13-40` `FriendlyTokens` will collapse into thin shims importing from Core. *Why:* eliminates 3-way drift; share extension and widget can't otherwise share tokens.

2. **Dark mode scope:** First-class secondary. Both light and dark must be visually QA'd on every change. Not "fallback only." *Why:* iOS users keep system theme on dark widely; the brand should look intentional in both.

3. **Onboarding color scheme lock:** `OnboardingView` keeps `.preferredColorScheme(.light)`. *Why:* the onboarding hero is the single brand impression at first launch and Friendly is light-first; the user's system theme overrides everywhere else.

4. **macOS menu bar popover:** Light ground in Friendly (matches the system menu bar light context). *Why:* consistency with iOS Friendly + natural contrast against the system menu bar background. Dark theme of the popover follows when the user's system is dark.

5. **Amber accent sunset:** Refactor any remaining hardcoded `.amberAccent` references to the semantic `.accent` (now violet) during the next migration touch. *Why:* prevents future drift; amber is now exclusively `accentHot` token, not a separate accent system.

6. **`.design-handoff/project/` Swift files:** Treated as **starting points**, not drop-in canonical sources. The current single-page onboarding + adaptive scene structure in `apple/FastSharedApp/Scenes/` is the target architecture. *Why:* `apple/` already shipped a redesign; restructuring scenes again would create churn for no design gain.

---

## Risk Surfaces (be careful when touching)

1. **Live Activity widget rendering.** Widget extension only imports `FastSharedCore.BrandPalette`. Color reference changes must update widget in lockstep. High coupling, no compile-time check across targets for visual consistency.

2. **Share Extension memory limits.** ShareExt has tight memory budget. Importing from Core (Phase 1) is fine, but adding heavy dependencies or assets will trigger termination. Test on real device after token consolidation.

3. **macOS menu bar popover sizing.** `MacMenuBarView.swift` and `MacCompanionView.swift` have fragile frame constraints. Changes to padding/radius tokens may cascade into clipping or overflow. Test on macOS after every token change.

4. **Color Asset catalog references.** `Assets.xcassets` may still embed old warm-amber Color sets. `Color("AmberHot")` style references will continue to pick stale values until assets are audited (Phase 3).

5. **Onboarding `preferredColorScheme(.light)`.** Forces light even when system is dark. Status bar style and system chrome may clash on dark devices — verify status bar uses dark content (`statusBarStyle = .darkContent`) so it remains legible on the cream ground.

---

## Migration Plan (apply Friendly to apple/)

Current state: ~85% aligned. The work is **consolidation**, not redesign.

| Phase | Goal | Files | Complexity | Risk |
|---|---|---|---|---|
| **1** | **Token consolidation** — single source of truth in `FastSharedCore.FriendlyPalette` | `Packages/FastSharedCore/.../BrandPalette.swift`, `apple/FastSharedApp/Components/BrandPalette+Redesign.swift`, `apple/FastSharedShareExt/ShareRootView.swift:13-40`, `apple/FastSharedLiveActivity/FastSharedUploadLiveActivity.swift:15-32` | Small | Low (compile-time check catches drift) |
| **2** | **Canvas & ground bleed** — root background swaps to Friendly ground (light/dark adaptive) | `RootView.swift`, scene roots | Small | Low |
| **3** | **Asset catalog audit** — remove stale warm-amber Color sets from `Assets.xcassets` | `apple/FastSharedApp/Resources/Assets.xcassets/` | Medium | Medium (silent breaks if asset name still referenced) |
| **4** | **Live Activity polish** — verify all color references go through Phase 1 tokens; visual QA on Lock Screen + Dynamic Island | `FastSharedLiveActivity/FastSharedUploadLiveActivity.swift`, `Packages/FastSharedCore/.../LiveActivityController.swift` | Medium | Medium (widget rendering is fussy; needs device testing iOS 17+) |

Total estimated time: 8-10 hours. Recommend landing as 2 PRs: Phase 1+2 (tokens + ground), then Phases 3+4 (assets + Live Activity).

---

## Working Notes for Future Sessions

- Friendly Swift source code lives in `.design-handoff/project/` as a reference. Treat as starting points, not drop-in copies.
- The `redesign-decisions.md` memory entry is from the PREVIOUS (warm-amber) redesign cycle. Friendly supersedes the visual decisions there but inherits the structural ones (single-page onboarding, Hub refactor, full feature scope).
- `BrandShapes.swift` is a foundation primitive (rounded rect helpers) — reuse, don't recreate.
- When adding a new surface, first check if it can compose existing components (`Ring`, `BrandLockup`, `FileGlyph`, `Mono`, `ExpiryTier`). The component library is comprehensive.
- Reduced-motion testing: enable in Simulator via Settings → Accessibility → Motion → Reduce Motion before merging any animation change.
