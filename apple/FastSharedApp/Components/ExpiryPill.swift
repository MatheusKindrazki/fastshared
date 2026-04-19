import SwiftUI
import FastSharedCore

/// Mono-pill countdown readout. The technical voice of the hub.
///
/// Color rules:
///  > 6h       — amber
///  ≤ 6h       — ember
///  ≤ 30m      — coral
///  ≤ 1m       — coral, blinking cream on a 1s pulse
///  expired    — milk-dim, no accent
struct ExpiryPill: View {
    let remaining: TimeInterval?
    let date: Date
    var size: Size = .small

    enum Size {
        case small  // hero sidecar
        case row    // per-row countdown
        case jumbo  // DetailView hero
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let seconds = remaining ?? 0
        let text = remaining == nil ? "expired" : ExpiryFormatter.remaining(seconds)
        let color = tint(for: remaining)

        TimelineView(.periodic(from: date, by: 1)) { timeline in
            let blinkOn = shouldBlink(remaining: remaining) && pulse(timeline: timeline)

            Text(text)
                .font(font(blinking: blinkOn))
                .monospacedDigit()
                .tracking(size == .jumbo ? -0.5 : 0)
                .foregroundStyle(blinkOn && !reduceMotion ? BrandPalette.dust : color)
                .padding(.horizontal, padHorizontal)
                .padding(.vertical, padVertical)
                .background(
                    Capsule().stroke(color.opacity(size == .jumbo ? 0 : 0.35), lineWidth: 1)
                )
                .contentTransition(.numericText(countsDown: true))
        }
        .accessibilityLabel(remaining == nil ? "Expired" : "Expires in \(text)")
    }

    private func shouldBlink(remaining: TimeInterval?) -> Bool {
        guard let remaining else { return false }
        return remaining > 0 && remaining <= 60
    }

    private func pulse(timeline: TimelineViewDefaultContext) -> Bool {
        // On/off every second — the "heartbeat" of impending death.
        Int(timeline.date.timeIntervalSince1970) % 2 == 0
    }

    private func tint(for remaining: TimeInterval?) -> Color {
        guard let remaining, remaining > 0 else { return BrandPalette.milk.opacity(0.45) }
        if remaining <= 30 * 60 { return BrandPalette.coral }
        if remaining <= 6 * 3600 { return BrandPalette.ember }
        return BrandPalette.amber
    }

    private func font(blinking: Bool) -> Font {
        switch size {
        case .small: return .system(size: 13, weight: .semibold, design: .monospaced)
        case .row:   return .system(size: 19, weight: .semibold, design: .monospaced)
        case .jumbo: return .system(size: 68, weight: .bold, design: .monospaced)
        }
    }

    private var padHorizontal: CGFloat {
        switch size {
        case .small: return 10
        case .row:   return 0
        case .jumbo: return 0
        }
    }

    private var padVertical: CGFloat {
        switch size {
        case .small: return 5
        case .row:   return 0
        case .jumbo: return 0
        }
    }
}

/// Thin horizontal bar conveying how close the soonest link is to death.
/// Full amber when > 24h, amber→coral as it approaches zero, nearly-empty coral when under 30m.
struct UrgencySparkBar: View {
    let remaining: TimeInterval?

    private var fraction: Double {
        // 24h is "calm full", 0s is "dead". Linear with a soft floor so < 30m still shows a sliver.
        guard let remaining, remaining > 0 else { return 0 }
        let ceiling: Double = 24 * 3600
        let raw = min(1.0, max(0.05, remaining / ceiling))
        return raw
    }

    private var gradient: LinearGradient {
        guard let remaining, remaining > 0 else {
            return LinearGradient(colors: [BrandPalette.milk.opacity(0.15), BrandPalette.milk.opacity(0.05)],
                                  startPoint: .leading, endPoint: .trailing)
        }
        if remaining <= 30 * 60 {
            return LinearGradient(colors: [BrandPalette.coral, BrandPalette.coral.opacity(0.4)],
                                  startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(colors: [BrandPalette.amber, BrandPalette.coral],
                              startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BrandPalette.milk.opacity(0.06))
                Capsule()
                    .fill(gradient)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 2)
        .animation(BrandMotion.transition, value: fraction)
    }
}
