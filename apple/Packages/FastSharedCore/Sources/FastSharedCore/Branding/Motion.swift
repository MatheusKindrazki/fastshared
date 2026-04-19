import Foundation
import SwiftUI

public enum BrandMotion {
    /// The canonical spring for state transitions across the app. Slow, intentional, 0.45s.
    public static let transition: Animation = .spring(duration: 0.45, bounce: 0.25)

    /// The slow amber pulse used around uploads. 1.6s cycle, mirroring the origin sphere.
    public static let pulse: Animation = .easeInOut(duration: 1.6).repeatForever(autoreverses: true)

    /// Collapsed animation when Reduce Motion is enabled — no repeating motion, instant transitions.
    public static func respectReducedMotion(_ reduced: Bool, animation: Animation) -> Animation? {
        reduced ? nil : animation
    }
}
