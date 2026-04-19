import Foundation
import SwiftUI

/// fastshared brand palette. "Temporal link" — a warm origin sphere emits an arc that fades into particles.
/// These colors are the entire vocabulary; no other hues ship.
public enum BrandPalette {
    // Grounds / surfaces
    public static let ink = Color(red: 0x07 / 255.0, green: 0x03 / 255.0, blue: 0x18 / 255.0)
    public static let nightshade = Color(red: 0x14 / 255.0, green: 0x0a / 255.0, blue: 0x33 / 255.0)
    public static let violet = Color(red: 0x2a / 255.0, green: 0x14 / 255.0, blue: 0x58 / 255.0)

    // Accent progression — amber is the pulse, coral is the fade.
    public static let amber = Color(red: 0xff / 255.0, green: 0x9f / 255.0, blue: 0x47 / 255.0)
    public static let ember = Color(red: 0xff / 255.0, green: 0xc4 / 255.0, blue: 0x87 / 255.0)
    public static let coral = Color(red: 0xff / 255.0, green: 0x4e / 255.0, blue: 0x7c / 255.0)

    // Particle / highlight
    public static let dust = Color(red: 0xff / 255.0, green: 0xe0 / 255.0, blue: 0xb8 / 255.0)

    // Typography
    public static let milk = Color(red: 0xfa / 255.0, green: 0xfa / 255.0, blue: 0xff / 255.0)

    /// Amber → coral gradient. The signature "link fading out" motion.
    public static let arc = LinearGradient(
        colors: [amber, coral],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Dark surface gradient used as the share extension canvas.
    public static let canvas = LinearGradient(
        colors: [ink, nightshade, violet],
        startPoint: .top,
        endPoint: .bottom
    )
}
