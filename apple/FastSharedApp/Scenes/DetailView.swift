import SwiftUI
import SwiftData
import FastSharedCore

/// Link detail — `design/screens.jsx` → `Detail()`.
///
/// Composition (top → bottom):
///  - crumb ("‹ MANIFEST") + gear
///  - "24-hour link · active" mono kicker
///  - 30pt filename
///  - meta line (MIME · size · opens)
///  - big Ring (118pt) + expires / media-deleted sidecar
///  - URL card (tap-to-copy)
///  - metadata list with dashed dividers
///  - action dock (SHARE / OPEN / REVOKE)
struct DetailView: View {
    let linkID: PersistentIdentifier

    @Environment(\.modelContext) private var modelContext
    @Environment(\.clipboard) private var clipboard
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.dismiss) private var dismiss

    @State private var link: ShareLinkEntity?
    @State private var showRevokeConfirm = false
    @State private var revoking: Bool = false
    @State private var errorMessage: String?
    @State private var copyTick: Int = 0
    @State private var revokeTick: Int = 0

    var body: some View {
        ZStack {
            BrandPalette.ground.ignoresSafeArea()

            Group {
                if let link {
                    content(for: link)
                } else {
                    ProgressView()
                        .tint(BrandPalette.amberAccent.hot)
                }
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.text)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BrandPalette.ground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.success, trigger: copyTick)
        .sensoryFeedback(.impact(weight: .heavy), trigger: revokeTick)
        #endif
        .task(id: linkID) { await load() }
    }

    @ViewBuilder
    private func content(for link: ShareLinkEntity) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let remaining = max(0, link.expiresAt.timeIntervalSince(now))
            let retention = max(0, link.expiresAt.timeIntervalSince(link.createdAt))
            let progress = retention > 0 ? max(0, min(1, remaining / retention)) : 0

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    chromeBar

                    statusHeader(link: link)
                        .padding(.top, 28)

                    countdown(link: link, remaining: remaining, progress: progress)
                        .padding(.top, 30)

                    urlCard(link: link)
                        .padding(.top, 24)

                    metadataSection(link: link)
                        .padding(.top, 22)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(BrandPalette.amberAccent.fade)
                            .padding(.top, 10)
                    }

                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) {
            actionDock(link: link)
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
        }
        .confirmationDialog("Revoke this link?",
                            isPresented: $showRevokeConfirm,
                            titleVisibility: .visible) {
            Button("Revoke link", role: .destructive) {
                revokeTick &+= 1
                Task { await revoke(link) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone with the link will lose access immediately. The media is still deleted on the scheduled date.")
        }
    }

    // MARK: - Sections

    private var chromeBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("MANIFEST")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundStyle(BrandPalette.textDim)
            Spacer()
        }
    }

    private func statusHeader(link: ShareLinkEntity) -> some View {
        let accent = BrandPalette.amberAccent
        return VStack(alignment: .leading, spacing: 10) {
            Mono("\(link.retention.displayName) link · \(statusLabel(for: link))",
                 color: accent.hot)

            Text(link.originalFilename ?? link.token)
                .font(.system(size: 30, weight: .bold))
                .tracking(-1.0)
                .lineSpacing(-2)
                .foregroundStyle(BrandPalette.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(link.contentType)
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                Text("·")
                Text("\(link.accessCount) opens")
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(BrandPalette.textFaint)
        }
    }

    private func countdown(link: ShareLinkEntity, remaining: TimeInterval, progress: Double) -> some View {
        HStack(alignment: .center, spacing: 22) {
            Ring(progress: progress,
                 size: 118,
                 stroke: 7,
                 label: compactRemaining(remaining),
                 sub: "REMAINING")

            VStack(alignment: .leading, spacing: 10) {
                Mono("expires", size: 10, color: BrandPalette.textFaint)
                Text(link.expiresAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(BrandPalette.text)

                Mono("media deleted", size: 10, color: BrandPalette.textFaint)
                    .padding(.top, 10)
                Text("24h after expiry")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(BrandPalette.textDim)
            }

            Spacer(minLength: 0)
        }
    }

    private func urlCard(link: ShareLinkEntity) -> some View {
        let accent = BrandPalette.amberAccent
        let urlString = link.shortURL.absoluteString
        return VStack(alignment: .leading, spacing: 8) {
            Mono("short url", color: BrandPalette.textFaint)

            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 0) {
                    Text("fastsha.red/s/")
                        .foregroundStyle(BrandPalette.text)
                    Text(link.token)
                        .foregroundStyle(accent.hot)
                }
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

                Spacer(minLength: 12)

                Button {
                    clipboard.copy(urlString)
                    copyTick &+= 1
                } label: {
                    Text("COPY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(accent.hot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BrandPalette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BrandPalette.lineStrong, lineWidth: 1)
                )
        )
    }

    private func metadataSection(link: ShareLinkEntity) -> some View {
        let accent = BrandPalette.amberAccent
        let rows: [(String, String)] = [
            ("created",   link.createdAt.formatted(date: .abbreviated, time: .shortened)),
            ("retention", link.retention.displayName),
            ("status",    statusLabel(for: link)),
            ("token",     link.token.lowercased()),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            Mono("metadata", color: accent.hot)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Mono(row.0, size: 10, track: 1.2, color: BrandPalette.textFaint)
                            .frame(width: 110, alignment: .leading)
                        Text(row.1)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(BrandPalette.textDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        DashedDivider()
                    }
                }
            }
        }
    }

    private func actionDock(link: ShareLinkEntity) -> some View {
        let isActive = link.status == .active && link.expiresAt > .now
        return HStack(spacing: 8) {
            #if os(iOS)
            ShareLink(item: link.shortURL) {
                dockButtonLabel(title: "SHARE", destructive: false)
            }
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.4)
            #else
            Button { } label: { dockButtonLabel(title: "SHARE", destructive: false) }
                .buttonStyle(.plain)
                .disabled(!isActive)
            #endif

            Link(destination: link.shortURL) {
                dockButtonLabel(title: "OPEN", destructive: false)
            }
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.4)

            Button {
                showRevokeConfirm = true
            } label: {
                dockButtonLabel(title: "REVOKE", destructive: true)
            }
            .buttonStyle(.plain)
            .disabled(!isActive || revoking)
            .opacity(isActive && !revoking ? 1 : 0.4)
        }
    }

    private func dockButtonLabel(title: String, destructive: Bool) -> some View {
        let accent = BrandPalette.amberAccent
        let color = destructive ? accent.fade : BrandPalette.text
        let stroke = destructive ? accent.fade.opacity(0.33) : BrandPalette.lineStrong
        return Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BrandPalette.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
            )
    }

    // MARK: - Helpers

    private func statusLabel(for link: ShareLinkEntity) -> String {
        switch link.status {
        case .active: return "active"
        case .expired: return "expired"
        case .revoked: return "revoked"
        }
    }

    private func compactRemaining(_ s: TimeInterval) -> String {
        let seconds = Int(max(0, s))
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds/60)m" }
        if seconds < 86_400 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        let d = seconds / 86_400
        let h = (seconds % 86_400) / 3600
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }

    private func load() async {
        let descriptor = FetchDescriptor<ShareLinkEntity>()
        if let results = try? modelContext.fetch(descriptor) {
            link = results.first(where: { $0.persistentModelID == linkID })
        }
    }

    private func revoke(_ link: ShareLinkEntity) async {
        guard let orchestrator else {
            errorMessage = "Revoke is unavailable in this build."
            return
        }
        revoking = true
        defer { revoking = false }
        do {
            try await orchestrator.revoke(token: link.token)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A 1-pixel horizontal dashed divider with a minimal footprint.
private struct DashedDivider: View {
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundStyle(BrandPalette.line)
            .frame(height: 1)
    }
}
