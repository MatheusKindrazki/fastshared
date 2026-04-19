import SwiftUI
import FastSharedCore

/// One link in the hub ledger. Editorial, no card chrome — negative space is the chrome.
struct LinkRow: View {
    let link: ShareLinkEntity
    let now: Date
    let onCopy: () -> Void
    let onRevoke: () -> Void

    private var remaining: TimeInterval { max(0, link.expiresAt.timeIntervalSince(now)) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                Text(link.originalFilename ?? link.token)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BrandPalette.milk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                meta
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var icon: some View {
        ZStack {
            Circle()
                .stroke(BrandPalette.amber.opacity(0.35), lineWidth: 1)
                .frame(width: 44, height: 44)
            Image(systemName: iconName(for: link.contentType))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(BrandPalette.dust)
        }
        .accessibilityHidden(true)
    }

    private var meta: some View {
        HStack(spacing: 8) {
            Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
            dot
            Text("\(link.token.count) chars")
            dot
            Text(ExpiryFormatter.createdAgo(link.createdAt, now: now))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .tracking(0.4)
        .foregroundStyle(BrandPalette.milk.opacity(0.45))
        .lineLimit(1)
    }

    private var dot: some View {
        Text("·")
            .foregroundStyle(BrandPalette.milk.opacity(0.28))
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ExpiryPill(remaining: remaining > 0 ? remaining : nil, date: now, size: .row)
            Text(label(for: link))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.milk.opacity(0.35))
        }
    }

    private func label(for link: ShareLinkEntity) -> String {
        if link.linkStatus == LinkStatus.revoked.rawValue { return "REVOKED" }
        if remaining <= 0 { return "DELETED IN —" }
        return "EXPIRES"
    }

    private func iconName(for contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType.hasPrefix("video/") { return "film" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        if contentType == "application/pdf" { return "doc.richtext" }
        if contentType.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }
}

/// Full-width monospace section header, set in small caps with a thin amber rule.
struct SectionHeaderStylized: View {
    let title: String
    let accent: Color
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(accent)
            Rectangle()
                .fill(accent.opacity(0.25))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            Text(String(format: "%02d", count))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(accent.opacity(0.6))
        }
        .padding(.vertical, 8)
    }
}
