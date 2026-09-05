import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// FastShared brand palette — v2 "warm amber on ink".
///
/// Ported 1:1 from `project/design/tokens.js` (the Claude Design handoff):
/// a warm origin sphere on an ink ground, amber as the heat point, coral/fade as risk.
/// All semantic tokens live under the top-level namespace; the `amber/violet/mint`
/// accent palettes expose the `.hot / .soft / .fade / .dust` progression.
///
/// The original v1 teal/green token names remain as deprecated aliases so pre-redesign
/// consumers keep compiling. New code MUST use the semantic tokens below.
public enum BrandPalette {

    // MARK: - Grounds & surfaces (dark theme is primary)

    /// Deepest ground. Full-bleed backgrounds.
    public static let ground = Color(red: 0x07 / 255.0, green: 0x03 / 255.0, blue: 0x18 / 255.0)
    /// Elevated tier 0 — large sheets, Mac window chrome.
    public static let surface0 = Color(red: 0x0f / 255.0, green: 0x06 / 255.0, blue: 0x30 / 255.0)
    /// Elevated tier 1 — screenshot banner, cards.
    public static let surface1 = Color(red: 0x1d / 255.0, green: 0x0d / 255.0, blue: 0x4b / 255.0)
    /// Elevated tier 2 — heavier accents, thumbnail fills.
    public static let surface2 = Color(red: 0x3b / 255.0, green: 0x1f / 255.0, blue: 0x86 / 255.0)

    /// Translucent "paper" fill for inline chips / cards.
    public static let paper = Color.white.opacity(0.04)

    // MARK: - Lines

    /// Hairline divider.
    public static let line = Color.white.opacity(0.08)
    /// Emphasized divider.
    public static let lineStrong = Color.white.opacity(0.16)

    // MARK: - Text

    /// Primary text.
    public static let text = Color(red: 0xfa / 255.0, green: 0xfa / 255.0, blue: 0xff / 255.0)
    /// Secondary text.
    public static let textDim = Color(red: 0xfa / 255.0, green: 0xfa / 255.0, blue: 0xff / 255.0).opacity(0.62)
    /// Faint text for captions / mono ledger.
    public static let textFaint = Color(red: 0xfa / 255.0, green: 0xfa / 255.0, blue: 0xff / 255.0).opacity(0.34)

    // MARK: - Accent palettes

    /// Accent palette exposes a four-step progression. Built from `tokens.js`.
    public struct Accent: Sendable {
        /// Hot point. Primary action color, ring stroke.
        public let hot: Color
        /// Soft wash. Gradient mid-stop, halos.
        public let soft: Color
        /// Fade — the "dying" terminus. Used for risk / revoke.
        public let fade: Color
        /// Dust — trailing particles after the arc dissipates.
        public let dust: Color
    }

    /// Primary accent. Warm amber → ember → pink fade → dust.
    public static let amberAccent = Accent(
        hot:  Color(red: 0xff / 255.0, green: 0x9f / 255.0, blue: 0x47 / 255.0),
        soft: Color(red: 0xff / 255.0, green: 0xc4 / 255.0, blue: 0x87 / 255.0),
        fade: Color(red: 0xff / 255.0, green: 0x4e / 255.0, blue: 0x7c / 255.0),
        dust: Color(red: 0xff / 255.0, green: 0xe0 / 255.0, blue: 0xb8 / 255.0)
    )

    /// Cool violet accent (alternate theme).
    public static let violetAccent = Accent(
        hot:  Color(red: 0x9d / 255.0, green: 0x7a / 255.0, blue: 0xff / 255.0),
        soft: Color(red: 0xc1 / 255.0, green: 0xa9 / 255.0, blue: 0xff / 255.0),
        fade: Color(red: 0xff / 255.0, green: 0x7a / 255.0, blue: 0xd1 / 255.0),
        dust: Color(red: 0xe0 / 255.0, green: 0xd4 / 255.0, blue: 0xff / 255.0)
    )

    /// Mint accent (alternate theme).
    public static let mintAccent = Accent(
        hot:  Color(red: 0x4d / 255.0, green: 0xdb / 255.0, blue: 0xb0 / 255.0),
        soft: Color(red: 0x87 / 255.0, green: 0xeb / 255.0, blue: 0xcf / 255.0),
        fade: Color(red: 0xff / 255.0, green: 0x9f / 255.0, blue: 0x47 / 255.0),
        dust: Color(red: 0xc7 / 255.0, green: 0xf2 / 255.0, blue: 0xe3 / 255.0)
    )

    // MARK: - Semantic accent helper
    //
    // The brand ships with **violet** as the unified accent. Views must read
    // `BrandPalette.accent` (or the app-target shim `BrandPalette.accentHot`)
    // rather than reaching into a named accent palette directly. The
    // `amberAccent` palette is retained only for the urgency-warning gradient
    // (`BrandPalette.arc`) and legacy compatibility presets.
    public static let accent: Accent = violetAccent

    // MARK: - Gradients

    /// The signature "link transfer" stroke gradient. amber soft → hot → fade.
    public static let arc = LinearGradient(
        colors: [amberAccent.soft, amberAccent.hot, amberAccent.fade],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Full-bleed canvas. Dark ground with a subtle violet wash.
    public static let canvas = LinearGradient(
        colors: [ground, surface0.opacity(0.8), ground],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Deprecated v1 aliases (teal/green palette → warm amber)
    //
    // These preserve the old names so existing consumers keep compiling.
    // New code should use the semantic tokens above (`ground`, `text`, `textDim`,
    // `amberAccent.hot`, etc). A follow-up PR will migrate existing call sites.

    /// Old ink (near-black) — now maps to `ground`.
    @available(*, deprecated, renamed: "ground")
    public static let ink = ground

    /// Old nightshade surface — now maps to `surface0`.
    @available(*, deprecated, renamed: "surface0")
    public static let nightshade = surface0

    /// Old violet accent — now maps to `surface2`.
    @available(*, deprecated, renamed: "surface2")
    public static let violet = surface2

    /// Old teal accent (#00a69c) — now maps to the amber hot point.
    @available(*, deprecated, renamed: "amberAccent.hot")
    public static let amber = amberAccent.hot

    /// Old green accent (#4ecf8f) — now maps to amber soft wash.
    @available(*, deprecated, renamed: "amberAccent.soft")
    public static let ember = amberAccent.soft

    /// Old coral accent — now maps to amber fade (pink terminus).
    @available(*, deprecated, renamed: "amberAccent.fade")
    public static let coral = amberAccent.fade

    /// Old secondary text — now maps to `textDim`.
    @available(*, deprecated, renamed: "textDim")
    public static let dust = textDim

    /// Old typography color — now maps to `text`.
    @available(*, deprecated, renamed: "text")
    public static let milk = text

    /// Old frost surface — now maps to `surface0`.
    @available(*, deprecated, renamed: "surface0")
    public static let frost = surface0

    /// Old light text — kept (white) for pill backgrounds.
    public static let lightText = Color.white
}

// MARK: - FriendlyPalette
//
// Single source of truth for the Friendly redesign tokens, shared across the
// app target, share extension, and Live Activity widget. Values mirror
// `apple/design-system/MASTER.md`. The legacy `BrandPalette` warm-amber-on-ink
// surface above is retained until Phase 3 deprecation.

private extension Color {
    /// Hex string parser scoped to FriendlyPalette. Accepts `RRGGBB` or
    /// `RRGGBBAA` with optional leading `#`. Falls back to opaque black on
    /// malformed input — token literals are constants, so failure is a coding
    /// error caught in QA, not a runtime concern.
    init(friendlyHex hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xff) / 255.0
            g = Double((v >> 8)  & 0xff) / 255.0
            b = Double( v        & 0xff) / 255.0
            a = 1.0
        case 8:
            r = Double((v >> 24) & 0xff) / 255.0
            g = Double((v >> 16) & 0xff) / 255.0
            b = Double((v >> 8)  & 0xff) / 255.0
            a = Double( v        & 0xff) / 255.0
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

public enum FriendlyPalette {

    // MARK: Theme-aware surface tokens

    public static func ground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkGround : lightGround
    }
    public static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkCanvas : lightCanvas
    }
    public static func surface0(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurface0 : lightSurface0
    }
    public static func surface1(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurface1 : lightSurface1
    }
    public static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkPaper : lightPaper
    }
    public static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkLine : lightLine
    }
    public static func lineStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkLineStrong : lightLineStrong
    }
    public static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkText : lightText
    }
    public static func textDim(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTextDim : lightTextDim
    }
    public static func textFaint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTextFaint : lightTextFaint
    }

    // MARK: Theme-independent accents
    //
    // Brand accent unified on violet. Amber (`#ff9f47`) is reserved for
    // urgency warning semantics via `UrgencyTier.warning.text`.
    public static let accentHot   = Color(friendlyHex: "9d7aff")
    public static let accentSoft  = Color(friendlyHex: "c1a9ff")
    public static let accentFade  = Color(friendlyHex: "ff7ad1")
    public static let accentDust  = Color(friendlyHex: "e0d4ff")
    public static let successGreen = Color(friendlyHex: "22c27a")

    // MARK: Urgency tiers

    public enum UrgencyTier {
        case critical, warning, normal, calm

        public var text: Color {
            switch self {
            case .critical: return Color(friendlyHex: "ff4e7c")
            case .warning:  return Color(friendlyHex: "ff9f47")
            case .normal:   return Color(friendlyHex: "9d7aff")
            case .calm:     return Color(friendlyHex: "6b5fb8")
            }
        }

        public func bg(_ scheme: ColorScheme) -> Color {
            switch (self, scheme) {
            case (.critical, .dark): return Color(friendlyHex: "3d0f22")
            case (.critical, _):     return Color(friendlyHex: "fff0f4")
            case (.warning,  .dark): return Color(friendlyHex: "3d2410")
            case (.warning,  _):     return Color(friendlyHex: "fff5e8")
            case (.normal,   .dark): return Color(friendlyHex: "2a1a5e")
            case (.normal,   _):     return Color(friendlyHex: "f3eeff")
            case (.calm,     .dark): return Color(friendlyHex: "1f1847")
            case (.calm,     _):     return Color(friendlyHex: "ece8f7")
            }
        }
    }

    // MARK: Spacing

    public enum Spacing {
        public static let xs:  CGFloat = 6
        public static let sm:  CGFloat = 10
        public static let md:  CGFloat = 16
        public static let lg:  CGFloat = 24
        public static let xl:  CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    // MARK: Radius

    public enum Radius {
        public static let sm:   CGFloat = 10
        public static let md:   CGFloat = 14
        public static let lg:   CGFloat = 20
        public static let xl:   CGFloat = 28
        public static let pill: CGFloat = 999
    }

    // MARK: Neutral chrome (the system ramp the app actually ships)
    //
    // The Friendly *dark* tokens above are a deep navy-purple (#0d0625 ground,
    // #1a0f4a paper). As app chrome they make every dark surface read as "a
    // purple app" — violet is the brand ACCENT, not the ground. That leak has
    // already been reported once by users and fixed once: see the comment on
    // `FastSharedApp/Scenes/HistoryView.swift:45-48` — "users reclamaram que a
    // Home ficava roxa no dark mode" — which resolved it by moving chrome onto
    // the platform's semantic ramp in BOTH appearances.
    //
    // The share extension had the same ramp, file-privately, until commit
    // 61b9667 ("fix: make share extension link screen full screen", 2026-06-15)
    // deleted the helpers and reverted every call site to
    // `FriendlyPalette.*(colorScheme)` — a palette regression riding on a layout
    // commit. These accessors are that ramp restored, and hoisted into Core so
    // it has one home instead of being re-declared per target: the extension
    // compiles only `FastSharedShareExt` plus this package (`project.yml:194-202`),
    // and `Color.sysBackground` & friends are `internal` to the app module
    // (`BrandPalette+Redesign.swift:78`), so the extension could never have
    // reached them. MASTER.md principle 5, "one token source".
    //
    // These are deliberately NOT `(ColorScheme) -> Color`: the underlying
    // platform colors are already dynamic, so a scheme argument would invite a
    // caller to pin one appearance. Views that genuinely want a literal Friendly
    // token still call `ground(_:)` / `paper(_:)` / `text(_:)`.
    //
    // Platform colors are wrapped explicitly (`Color(uiColor:)` / `Color(nsColor:)`).
    // Never write `var sysBackground: Color { sysBackground }` — that shape shipped
    // once and crashed the extension with infinite recursion (7f2ab52, "Fix share
    // extension color recursion crash").
    //
    // ⚠️ Measured, and NOT a bug: inside the modally-presented share sheet these
    // render one step lighter than on a base screen — dark ground #1c1c1e, cards
    // #2c2c2e, not #000000/#1c1c1e. That is UIKit's `elevated` background set,
    // which iOS applies to modal content in dark mode so a sheet reads as raised
    // above its host. Do not "correct" it by hardcoding the base values; that
    // would flatten the sheet against the host app.

    /// Full-bleed background of a hand-composed screen.
    public static var neutralGround: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// Cards and wells sitting on `neutralGround`.
    public static var neutralCard: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    /// Subtle fill nested *inside* a card (icon tiles).
    public static var neutralWell: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .tertiarySystemBackground)
        #endif
    }

    /// Primary text.
    public static var neutralText: Color {
        #if os(macOS)
        Color(nsColor: .labelColor)
        #else
        Color(uiColor: .label)
        #endif
    }

    /// Secondary text.
    public static var neutralTextDim: Color {
        #if os(macOS)
        Color(nsColor: .secondaryLabelColor)
        #else
        Color(uiColor: .secondaryLabel)
        #endif
    }

    /// Tertiary / metadata text.
    public static var neutralTextFaint: Color {
        #if os(macOS)
        Color(nsColor: .tertiaryLabelColor)
        #else
        Color(uiColor: .tertiaryLabel)
        #endif
    }

    /// Hairline borders and progress tracks.
    public static var neutralLine: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }

    // MARK: Underlying constants
    //
    // File-private storage so the theme-aware accessors above don't recompute
    // per call. Public API stays the `(_:ColorScheme) -> Color` functions —
    // views must not reach in here directly.

    private static let lightGround       = Color(friendlyHex: "fbf8f1")
    private static let lightCanvas       = Color(friendlyHex: "ffffff")
    private static let lightSurface0     = Color(friendlyHex: "f5f1e6")
    private static let lightSurface1     = Color(friendlyHex: "eae4d4")
    private static let lightPaper        = Color(friendlyHex: "ffffff")
    private static let lightLine         = Color(friendlyHex: "211244").opacity(0.08)
    private static let lightLineStrong   = Color(friendlyHex: "211244").opacity(0.16)
    private static let lightText         = Color(friendlyHex: "1a0f38")
    private static let lightTextDim      = Color(friendlyHex: "1a0f38").opacity(0.64)
    private static let lightTextFaint    = Color(friendlyHex: "1a0f38").opacity(0.40)

    private static let darkGround        = Color(friendlyHex: "0d0625")
    private static let darkCanvas        = Color(friendlyHex: "140a38")
    private static let darkSurface0      = Color(friendlyHex: "1a0f4a")
    private static let darkSurface1      = Color(friendlyHex: "281664")
    private static let darkPaper         = Color(friendlyHex: "1a0f4a")
    private static let darkLine          = Color.white.opacity(0.09)
    private static let darkLineStrong    = Color.white.opacity(0.18)
    private static let darkText          = Color(friendlyHex: "f7f4ff")
    private static let darkTextDim       = Color(friendlyHex: "f7f4ff").opacity(0.66)
    private static let darkTextFaint     = Color(friendlyHex: "f7f4ff").opacity(0.38)
}
