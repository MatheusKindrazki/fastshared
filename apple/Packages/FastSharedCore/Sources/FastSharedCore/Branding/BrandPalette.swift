import Foundation
import SwiftUI

/// fastshared brand palette. "Frosted manifest" — temporary links sit on a bright glass
/// surface with a precise transfer rail. Color is reserved for action, freshness, and risk.
public enum BrandPalette {
    // Grounds / surfaces
    public static let ink = Color(red: 0x12 / 255.0, green: 0x16 / 255.0, blue: 0x1d / 255.0)
    public static let nightshade = Color(red: 0xf5 / 255.0, green: 0xf8 / 255.0, blue: 0xfb / 255.0)
    public static let violet = Color(red: 0xe7 / 255.0, green: 0xf2 / 255.0, blue: 0xef / 255.0)

    // Accent progression — teal is the transfer, green is fresh, coral is risk.
    public static let amber = Color(red: 0x00 / 255.0, green: 0xa6 / 255.0, blue: 0x9c / 255.0)
    public static let ember = Color(red: 0x4e / 255.0, green: 0xcf / 255.0, blue: 0x8f / 255.0)
    public static let coral = Color(red: 0xf0 / 255.0, green: 0x52 / 255.0, blue: 0x5f / 255.0)

    // Secondary text / quiet marks
    public static let dust = Color(red: 0x66 / 255.0, green: 0x70 / 255.0, blue: 0x85 / 255.0)

    // Typography
    public static let milk = ink

    public static let paper = Color(red: 0xfb / 255.0, green: 0xfc / 255.0, blue: 0xff / 255.0)
    public static let frost = Color(red: 0xec / 255.0, green: 0xf8 / 255.0, blue: 0xf6 / 255.0)
    public static let line = Color(red: 0xd7 / 255.0, green: 0xe1 / 255.0, blue: 0xe8 / 255.0)
    public static let lightText = Color.white

    /// Teal → green gradient. The signature "link transfer" motion.
    public static let arc = LinearGradient(
        colors: [amber, ember],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Bright frosted canvas used across the app and share extension.
    public static let canvas = LinearGradient(
        colors: [paper, frost, nightshade],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
