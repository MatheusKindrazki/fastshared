import SwiftUI
import FastSharedCore

// Backward-compat shim. The Friendly tokens themselves now live in
// `FastSharedCore.FriendlyPalette` (single source of truth across app, share
// extension, and Live Activity widget). This extension keeps the legacy
// `BrandPalette.friendly*` / `urgency*` member names alive so existing view
// call sites continue to compile while Phase 2+ migrates them to the
// `FriendlyPalette` API directly.
//
// The `accentHot` / `accentSoft` / `accentFade` / `accentDust` properties
// are inline violet hex literals matching the unified brand accent. The
// canonical accent now lives in `FriendlyPalette.accentHot` (also violet),
// so these app-target constants stay in lockstep with the core palette.
// Amber (`#ff9f47`) is reserved for urgency-warning semantics via
// `FriendlyPalette.UrgencyTier.warning.text`, not brand CTAs.

extension BrandPalette {

    // MARK: - Friendly Light Palette

    static var friendlyGround:     Color { FriendlyPalette.ground(.light) }
    static var friendlyCanvas:     Color { FriendlyPalette.canvas(.light) }
    static var friendlySurface0:   Color { FriendlyPalette.surface0(.light) }
    static var friendlySurface1:   Color { FriendlyPalette.surface1(.light) }
    static var friendlyText:       Color { FriendlyPalette.text(.light) }
    static var friendlyTextDim:    Color { FriendlyPalette.textDim(.light) }
    static var friendlyTextFaint:  Color { FriendlyPalette.textFaint(.light) }
    static var friendlyLine:       Color { FriendlyPalette.line(.light) }
    static var friendlyLineStrong: Color { FriendlyPalette.lineStrong(.light) }

    // MARK: - Friendly Dark Palette

    static var friendlyGroundDark:     Color { FriendlyPalette.ground(.dark) }
    static var friendlyCanvasDark:     Color { FriendlyPalette.canvas(.dark) }
    static var friendlySurface0Dark:   Color { FriendlyPalette.surface0(.dark) }
    static var friendlySurface1Dark:   Color { FriendlyPalette.surface1(.dark) }
    static var friendlyTextDark:       Color { FriendlyPalette.text(.dark) }
    static var friendlyTextDimDark:    Color { FriendlyPalette.textDim(.dark) }
    static var friendlyTextFaintDark:  Color { FriendlyPalette.textFaint(.dark) }
    static var friendlyLineDark:       Color { FriendlyPalette.line(.dark) }
    static var friendlyLineStrongDark: Color { FriendlyPalette.lineStrong(.dark) }

    // MARK: - Violet Accent Tokens (legacy app-target accent — see file note)

    static let accentHot   = Color(red: 0x9d / 255.0, green: 0x7a / 255.0, blue: 1.0)
    static let accentSoft  = Color(red: 0xc1 / 255.0, green: 0xa9 / 255.0, blue: 1.0)
    static let accentFade  = Color(red: 1.0, green: 0x7a / 255.0, blue: 0xd1 / 255.0)
    static let accentDust  = Color(red: 0xe0 / 255.0, green: 0xd4 / 255.0, blue: 1.0)

    // MARK: - Urgency tokens

    static var urgencyCritical: Color { FriendlyPalette.UrgencyTier.critical.text }
    static var urgencyWarning:  Color { FriendlyPalette.UrgencyTier.warning.text }
    static var urgencyNormal:   Color { FriendlyPalette.UrgencyTier.normal.text }
    static var urgencyCalm:     Color { FriendlyPalette.UrgencyTier.calm.text }

    static var urgencyCriticalBgLight: Color { FriendlyPalette.UrgencyTier.critical.bg(.light) }
    static var urgencyWarningBgLight:  Color { FriendlyPalette.UrgencyTier.warning.bg(.light) }
    static var urgencyNormalBgLight:   Color { FriendlyPalette.UrgencyTier.normal.bg(.light) }
    static var urgencyCalmBgLight:     Color { FriendlyPalette.UrgencyTier.calm.bg(.light) }

    static var urgencyCriticalBgDark: Color { FriendlyPalette.UrgencyTier.critical.bg(.dark) }
    static var urgencyWarningBgDark:  Color { FriendlyPalette.UrgencyTier.warning.bg(.dark) }
    static var urgencyNormalBgDark:   Color { FriendlyPalette.UrgencyTier.normal.bg(.dark) }
    static var urgencyCalmBgDark:     Color { FriendlyPalette.UrgencyTier.calm.bg(.dark) }

    // MARK: - Success

    static var successGreen: Color { FriendlyPalette.successGreen }
}
