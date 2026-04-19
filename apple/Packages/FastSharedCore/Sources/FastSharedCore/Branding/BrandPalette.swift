import Foundation
import SwiftUI

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
