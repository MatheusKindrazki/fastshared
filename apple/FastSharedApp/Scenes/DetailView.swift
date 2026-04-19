import SwiftUI
import SwiftData
import FastSharedCore

/// One link, close up. The countdown is the star — it occupies the optical center of the screen.
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
            BrandPalette.canvas.ignoresSafeArea()

            Group {
                if let link {
                    content(for: link)
                } else {
                    ProgressView()
                        .tint(BrandPalette.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.milk)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header(for: link, remaining: remaining)
                    countdown(for: link, remaining: remaining, now: now)
                    urlCard(for: link)
                    metaList(for: link)
                    actionRow(for: link, remaining: remaining)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(BrandPalette.coral)
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
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

    private func header(for link: ShareLinkEntity, remaining: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(retentionLabel(for: link).uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(BrandPalette.amber)

            Text(link.originalFilename ?? link.token)
                .font(.system(size: 34, weight: .bold))
                .tracking(-1.4)
                .foregroundStyle(BrandPalette.milk)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: iconName(for: link.contentType))
                    .font(.system(size: 11, weight: .medium))
                Text(link.contentType)
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                Text("·")
                Text("\(link.accessCount) opens")
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(BrandPalette.milk.opacity(0.5))
        }
        .padding(.top, 8)
    }

    private func countdown(for link: ShareLinkEntity, remaining: TimeInterval, now: Date) -> some View {
        let expired = remaining <= 0 || link.linkStatus != LinkStatus.active.rawValue
        return VStack(alignment: .leading, spacing: 8) {
            Text(expired ? "EXPIRED" : "EXPIRES IN")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(BrandPalette.milk.opacity(0.45))

            ExpiryPill(remaining: expired ? nil : remaining, date: now, size: .jumbo)

            Text(link.expiresAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(BrandPalette.milk.opacity(0.45))

            UrgencySparkBar(remaining: expired ? nil : remaining)
                .padding(.top, 8)
        }
        .padding(.vertical, 16)
    }

    private func urlCard(for link: ShareLinkEntity) -> some View {
        let urlString = link.shortURL.absoluteString
        return VStack(alignment: .leading, spacing: 8) {
            Text("SHORT URL")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(BrandPalette.milk.opacity(0.45))
            HStack(alignment: .center, spacing: 10) {
                Text(urlString)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(BrandPalette.milk)
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
                        .tracking(1.6)
                        .foregroundStyle(BrandPalette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(BrandPalette.amber, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandPalette.milk.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BrandPalette.amber.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func metaList(for link: ShareLinkEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("METADATA")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(BrandPalette.milk.opacity(0.45))

            VStack(spacing: 10) {
                metaRow("created", link.createdAt.formatted(date: .abbreviated, time: .shortened))
                metaRow("retention", link.retention.displayName)
                metaRow("status", statusLabel(for: link))
                metaRow("media deleted", link.deleteAfter.formatted(date: .abbreviated, time: .shortened))
                metaRow("token", link.token)
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(BrandPalette.milk.opacity(0.4))
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(BrandPalette.milk.opacity(0.85))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func actionRow(for link: ShareLinkEntity, remaining: TimeInterval) -> some View {
        let isActive = link.status == .active && remaining > 0
        HStack(spacing: 10) {
            ShareLink(item: link.shortURL) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().stroke(BrandPalette.milk.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(BrandPalette.milk.opacity(0.85))
            .disabled(!isActive)

            Link(destination: link.shortURL) {
                Label("Open", systemImage: "safari")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().stroke(BrandPalette.milk.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(BrandPalette.milk.opacity(0.85))
            .disabled(!isActive)

            Spacer()

            Button(role: .destructive) {
                showRevokeConfirm = true
            } label: {
                HStack(spacing: 6) {
                    if revoking {
                        ProgressView().controlSize(.small).tint(BrandPalette.coral)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("REVOKE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.6)
                }
                .foregroundStyle(BrandPalette.coral)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().stroke(BrandPalette.coral.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isActive || revoking)
        }
    }

    // MARK: - Helpers

    private func retentionLabel(for link: ShareLinkEntity) -> String {
        link.retention.displayName + " link"
    }

    private func statusLabel(for link: ShareLinkEntity) -> String {
        switch link.status {
        case .active: return "active"
        case .expired: return "expired"
        case .revoked: return "revoked"
        }
    }

    private func iconName(for contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType.hasPrefix("video/") { return "film" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        if contentType == "application/pdf" { return "doc.richtext" }
        if contentType.hasPrefix("text/") { return "doc.text" }
        return "doc"
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
