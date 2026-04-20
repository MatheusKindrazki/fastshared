import Foundation
import SwiftUI
import FastSharedCore

/// Urgency tiering for active share links. Drives section grouping + accent color choices on the hub.
///
/// The tiers are ordered by proximity to death:
/// - `.underOneMinute` blinks (immediate action).
/// - `.underOneHour`   is fade (coral terminus).
/// - `.underSixHours`  is hot.
/// - `.underOneDay`    is hot.
/// - `.later`          is soft.
/// - `.forever`        is reserved for links > 7d; currently the longest retention is 30d.
enum ExpiryTier: Int, CaseIterable, Hashable, Comparable {
    case underOneMinute
    case underOneHour
    case underSixHours
    case underOneDay
    case later
    case forever

    static func < (lhs: ExpiryTier, rhs: ExpiryTier) -> Bool { lhs.rawValue < rhs.rawValue }

    static func tier(for remaining: TimeInterval) -> ExpiryTier {
        if remaining <= 60 { return .underOneMinute }
        if remaining <= 3600 { return .underOneHour }
        if remaining <= 6 * 3600 { return .underSixHours }
        if remaining <= 24 * 3600 { return .underOneDay }
        if remaining <= 7 * 86_400 { return .later }
        return .forever
    }

    var headline: String {
        switch self {
        case .underOneMinute: return "ACTION NEEDED"
        case .underOneHour:   return "UNDER 1 HOUR"
        case .underSixHours:  return "LATER TODAY"
        case .underOneDay:    return "NEXT 24 HOURS"
        case .later:          return "LATER THIS WEEK"
        case .forever:        return "LONGER WINDOW"
        }
    }

    /// Semantic tier color — reads the current `BrandPalette.accent` (violet
    /// by default) so the whole ramp re-tints when the accent switches.
    var accent: Color {
        let a = BrandPalette.accent
        switch self {
        case .underOneMinute, .underOneHour: return a.fade
        case .underSixHours:                 return a.hot
        case .underOneDay:                   return a.hot
        case .later, .forever:               return a.soft
        }
    }

    /// Maps a domain-side `ExpiryTier` (6 cases) to the design-side
    /// `FriendlyPalette.UrgencyTier` (4 cases) so urgency colors come from
    /// the single token source. The two enums intentionally have different
    /// granularity: the domain tier resolves a specific time bucket; the
    /// design tier resolves a visual treatment.
    private var paletteTier: FriendlyPalette.UrgencyTier {
        switch self {
        case .underOneMinute:                            return .critical
        case .underOneHour, .underSixHours, .underOneDay: return .warning
        case .later:                                      return .normal
        case .forever:                                    return .calm
        }
    }

    /// Semantic urgency color driven by the static urgency palette.
    /// Stays constant regardless of accent theme — use this for countdown rings
    /// and urgency badges.
    var urgencyColor: Color { paletteTier.text }

    /// Urgency background color for light backgrounds.
    var urgencyBgLight: Color { paletteTier.bg(.light) }

    /// Urgency background color for dark backgrounds.
    var urgencyBgDark: Color { paletteTier.bg(.dark) }

    /// Short human-readable urgency label for badges and row subtitles.
    var urgencyLabel: String {
        switch self {
        case .underOneMinute:
            return "Expires soon"
        case .underOneHour, .underSixHours, .underOneDay:
            return "Expires today"
        case .later:
            return "Active"
        case .forever:
            return "Plenty of time"
        }
    }
}

enum ExpiryFormatter {
    /// SF Mono-friendly remaining countdown. Two units max, always technical-feeling.
    /// Examples: `23h 14m`, `4m 22s`, `<1m`, `3d 7h`.
    static func remaining(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "<1m" }
        if s < 3600 {
            let m = s / 60
            let r = s % 60
            if r == 0 { return "\(m)m" }
            return "\(m)m \(r)s"
        }
        if s < 86_400 {
            let h = s / 3600
            let m = (s % 3600) / 60
            if m == 0 { return "\(h)h" }
            return "\(h)h \(m)m"
        }
        let d = s / 86_400
        let h = (s % 86_400) / 3600
        if h == 0 { return "\(d)d" }
        return "\(d)d \(h)h"
    }

    static func createdAgo(_ date: Date, now: Date = Date()) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta/60))m ago" }
        if delta < 86_400 { return "\(Int(delta/3600))h ago" }
        return "\(Int(delta/86_400))d ago"
    }
}

/// Precomputed tier grouping and nearest-expiry summary. Computed per `TimelineView` tick so the hub
/// reshuffles itself as rows cross urgency thresholds.
struct ExpirySnapshot {
    let activeCount: Int
    let nearestExpiry: Date?
    let nearestRemaining: TimeInterval?
    let grouped: [(tier: ExpiryTier, links: [ShareLinkEntity])]

    static func empty() -> ExpirySnapshot {
        ExpirySnapshot(activeCount: 0, nearestExpiry: nil, nearestRemaining: nil, grouped: [])
    }

    static func build(from links: [ShareLinkEntity], now: Date) -> ExpirySnapshot {
        let active = links.filter { link in
            link.linkStatus == LinkStatus.active.rawValue && link.expiresAt > now
        }
        guard !active.isEmpty else { return .empty() }

        var buckets: [ExpiryTier: [ShareLinkEntity]] = [:]
        var nearest: Date?
        for link in active {
            let remaining = link.expiresAt.timeIntervalSince(now)
            let tier = ExpiryTier.tier(for: remaining)
            buckets[tier, default: []].append(link)
            if nearest == nil || link.expiresAt < nearest! {
                nearest = link.expiresAt
            }
        }

        // WHY: stable ordering — urgent first, then rows inside each bucket by who dies next.
        let ordered = ExpiryTier.allCases
            .compactMap { tier -> (tier: ExpiryTier, links: [ShareLinkEntity])? in
                guard let list = buckets[tier], !list.isEmpty else { return nil }
                let sorted = list.sorted { $0.expiresAt < $1.expiresAt }
                return (tier, sorted)
            }

        let remaining = nearest.map { $0.timeIntervalSince(now) }
        return ExpirySnapshot(activeCount: active.count,
                              nearestExpiry: nearest,
                              nearestRemaining: remaining,
                              grouped: ordered)
    }
}
