import Foundation

/// The three SKUs sold by FastShared Pro.
///
/// Product IDs are the canonical ASC identifiers; keep them in sync with
/// `apple/FastSharedApp/FastShared.storekit` (local testing) and the ASC
/// product registry (production).
public enum ProTier: String, Sendable, Codable, CaseIterable {
    case monthly
    case annual
    case lifetime

    /// Canonical App Store Connect product identifier.
    public var productID: String {
        switch self {
        case .monthly:  return "red.fastsha.pro.monthly"
        case .annual:   return "red.fastsha.pro.annual"
        case .lifetime: return "red.fastsha.pro.lifetime"
        }
    }
}
