import SwiftUI
import FastSharedCore

/// One link in the manifest. A frosted file slip with the expiry rail visible at a glance.
struct LinkRow: View {
    let link: ShareLinkEntity
    let now: Date
    let onCopy: () -> Void
    let onRevoke: () -> Void

    private var remaining: TimeInterval { max(0, link.expiresAt.timeIntervalSince(now)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 5) {
                    Text(link.originalFilename ?? link.token)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BrandPalette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(urlDisplay)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.amber)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                trailing
            }

            UrgencySparkBar(remaining: remaining > 0 ? remaining : nil)

            meta
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BrandPalette.line.opacity(0.7), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BrandPalette.amber.opacity(0.10))
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BrandPalette.amber.opacity(0.22), lineWidth: 1)
                )
            Image(systemName: iconName(for: link.contentType))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(BrandPalette.amber)
        }
        .accessibilityHidden(true)
    }

    private var meta: some View {
        HStack(spacing: 8) {
            Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
            dot
            Text(shortToken)
            dot
            Text(ExpiryFormatter.createdAgo(link.createdAt, now: now))
            Spacer(minLength: 0)
            Label("details", systemImage: "chevron.right")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(BrandPalette.dust.opacity(0.82))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .tracking(0.4)
        .foregroundStyle(BrandPalette.dust)
        .lineLimit(1)
    }

    private var dot: some View {
        Text("·")
            .foregroundStyle(BrandPalette.line)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ExpiryPill(remaining: remaining > 0 ? remaining : nil, date: now, size: .row)
            Text(label(for: link))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.dust)
        }
    }

    private var urlDisplay: String {
        let host = link.shortURL.host ?? "fastsha.red"
        let path = link.shortURL.path
        return path.isEmpty || path == "/" ? host : "\(host)\(path)"
    }

    private var shortToken: String {
        let prefix = link.token.prefix(4)
        let suffix = link.token.suffix(4)
        return "\(prefix)…\(suffix)"
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

/// Full-width section header, set as a small manifest divider.
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
                .fill(BrandPalette.line.opacity(0.9))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            Text(String(format: "%02d", count))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.dust)
        }
        .padding(.vertical, 8)
    }
}
