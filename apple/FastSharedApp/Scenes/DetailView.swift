import SwiftUI
import SwiftData
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

/// Link detail — HIG-native refactor.
///
/// Mirrors the HistoryView grammar: native `List(.insetGrouped)` for the
/// system-grouped background, `BrandLockup` in the toolbar principal slot,
/// and inline actions in dedicated sections instead of a floating dock.
///
/// Composition:
///  - Hero section (edge-to-edge): file glyph + filename + size/age +
///    urgency ring + countdown headline.
///  - Link section: monospaced short URL with Copy action.
///  - Details section: `LabeledContent` rows (Expires, Retention, Opens,
///    Last seen, Status).
///  - Files section (bundle only): one row per `BundledAssetEntity`.
///  - Actions section: Share, Open in browser, Revoke (destructive).
///
/// No hard-coded backgrounds — the list supplies `.systemGroupedBackground`
/// which respects light/dark automatically. Urgency color lives on the ring,
/// the countdown numeral, and the chip; rows stay neutral.
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
    #if os(iOS)
    @State private var shareURL: URL?
    #endif

    var body: some View {
        Group {
            if let link {
                content(for: link)
            } else {
                // Keep the same nav chrome while we hydrate from SwiftData.
                List { }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                    .overlay(ProgressView())
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BrandLockup(markSize: 22, textSize: 15)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("FastShared")
            }
        }
        .sensoryFeedback(.success, trigger: copyTick)
        .sensoryFeedback(.impact(weight: .heavy), trigger: revokeTick)
        .sheet(item: Binding(
            get: { shareURL.map { IdentifiableURL(url: $0) } },
            set: { shareURL = $0?.url }
        )) { wrapped in
            ShareSheet(items: [wrapped.url])
                .presentationDetents([.medium, .large])
        }
        #endif
        .task(id: linkID) { await load() }
        .confirmationDialog("Revoke this link?",
                            isPresented: $showRevokeConfirm,
                            titleVisibility: .visible) {
            Button("Revoke link", role: .destructive) {
                revokeTick &+= 1
                if let link { Task { await revoke(link) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone with the link will lose access immediately. The media is still deleted on the scheduled date.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for link: ShareLinkEntity) -> some View {
        // Ticks once per second so the countdown/ring stay live without a
        // separate timer plumbing; the List re-renders in place.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let remaining = max(0, link.expiresAt.timeIntervalSince(now))
            let retention = max(0, link.expiresAt.timeIntervalSince(link.createdAt))
            let progress = retention > 0 ? max(0, min(1, remaining / retention)) : 0
            let tier = ExpiryTier.tier(for: remaining)
            let isActive = link.status == .active && link.expiresAt > now

            List {
                heroSection(link: link, now: now, remaining: remaining, progress: progress, tier: tier, isActive: isActive)
                linkSection(link: link, isActive: isActive)
                detailsSection(link: link, now: now, tier: tier, isActive: isActive)
                if link.isBundle {
                    filesSection(link: link)
                }
                actionsSection(link: link, isActive: isActive)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
        }
    }

    // MARK: - Hero

    /// Edge-to-edge hero row. `listRowInsets(EdgeInsets())` lets us paint
    /// the full width; `.secondarySystemBackground` gives a subtle card
    /// contrast against the grouped background.
    @ViewBuilder
    private func heroSection(link: ShareLinkEntity,
                             now: Date,
                             remaining: TimeInterval,
                             progress: Double,
                             tier: ExpiryTier,
                             isActive: Bool) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    heroGlyph(link: link)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(link.originalFilename ?? link.token)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(.label))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(heroSubtitle(link: link, now: now))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if isActive {
                        UrgencyRing(progress: progress, size: 36, stroke: 4)
                            .accessibilityLabel("\(Int(progress * 100)) percent remaining")
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(countdownHeadline(remaining: remaining, tier: tier, isActive: isActive, status: link.status))
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(isActive ? tier.urgencyColor : Color(.secondaryLabel))
                    Text(countdownFootnote(link: link, isActive: isActive))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Link

    @ViewBuilder
    private func linkSection(link: ShareLinkEntity, isActive: Bool) -> some View {
        let urlString = link.shortURL.absoluteString
        Section {
            HStack(spacing: 12) {
                Text(urlString)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Button {
                    clipboard.copy(urlString)
                    copyTick &+= 1
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.titleOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isActive)
            }
        } header: {
            Text("Link")
        }
    }

    // MARK: - Details

    @ViewBuilder
    private func detailsSection(link: ShareLinkEntity,
                                now: Date,
                                tier: ExpiryTier,
                                isActive: Bool) -> some View {
        Section {
            LabeledContent("Status") {
                statusChip(link: link, tier: tier, isActive: isActive)
            }
            LabeledContent("Expires", value: link.expiresAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Retention", value: link.retention.displayName)
            LabeledContent("Opens") {
                Text("\(link.accessCount)")
                    .monospacedDigit()
            }
            LabeledContent("Last seen",
                           value: link.lastAccessedAt
                            .map { ExpiryFormatter.createdAgo($0, now: now) } ?? "Never")
            LabeledContent("Shared",
                           value: link.createdAt.formatted(date: .abbreviated, time: .shortened))
        } header: {
            Text("Details")
        }
    }

    // MARK: - Files (bundle)

    @ViewBuilder
    private func filesSection(link: ShareLinkEntity) -> some View {
        let files = link.bundledAssets.sorted { $0.displayOrder < $1.displayOrder }
        Section {
            ForEach(files, id: \.assetId) { asset in
                HStack(spacing: 12) {
                    FileGlyph(contentType: asset.contentType, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.filename)
                            .font(.body)
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(ByteCountFormatter.string(fromByteCount: asset.sizeBytes, countStyle: .file))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(files.count == 1 ? "1 file" : "\(files.count) files")
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionsSection(link: ShareLinkEntity, isActive: Bool) -> some View {
        Section {
            #if os(iOS)
            // Native ShareLink — matches system apps; offers all activity types.
            ShareLink(item: link.shortURL) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            .disabled(!isActive)
            #endif

            Link(destination: link.shortURL) {
                Label("Open in browser", systemImage: "safari")
            }
            .disabled(!isActive)

            Button(role: .destructive) {
                showRevokeConfirm = true
            } label: {
                Label("Stop sharing", systemImage: "xmark.circle")
            }
            .disabled(!isActive || revoking)
        }
    }

    // MARK: - Helpers

    /// Bundle rows use the stacked-doc glyph; single rows use FileGlyph.
    @ViewBuilder
    private func heroGlyph(link: ShareLinkEntity) -> some View {
        if link.isBundle {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        } else {
            FileGlyph(contentType: link.contentType, size: 48)
        }
    }

    private func heroSubtitle(link: ShareLinkEntity, now: Date) -> String {
        let size = ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file)
        let ago = ExpiryFormatter.createdAgo(link.createdAt, now: now)
        if link.isBundle {
            let n = max(link.bundledAssets.count, 1)
            let files = n == 1 ? "1 file" : "\(n) files"
            return "\(files) · \(size) · \(ago)"
        }
        return "\(size) · \(ago)"
    }

    private func countdownHeadline(remaining: TimeInterval,
                                   tier: ExpiryTier,
                                   isActive: Bool,
                                   status: LinkStatus) -> String {
        guard isActive else {
            return status == .revoked ? "Revoked" : "Expired"
        }
        return ExpiryFormatter.remaining(remaining)
    }

    private func countdownFootnote(link: ShareLinkEntity, isActive: Bool) -> String {
        guard isActive else { return "" }
        let cal = Calendar.current
        let time = link.expiresAt.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(link.expiresAt) {
            return "until \(time) today"
        } else if cal.isDateInTomorrow(link.expiresAt) {
            return "until \(time) tomorrow"
        } else {
            return "until \(link.expiresAt.formatted(.dateTime.month().day().hour().minute()))"
        }
    }

    private func statusChip(link: ShareLinkEntity, tier: ExpiryTier, isActive: Bool) -> some View {
        let (label, color): (String, Color) = {
            if !isActive {
                return link.status == .revoked
                    ? ("Revoked", Color(.secondaryLabel))
                    : ("Expired", Color(.secondaryLabel))
            }
            return (tier.urgencyLabel, tier.urgencyColor)
        }()
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
        }
    }

    // MARK: - Data

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

#if os(iOS)
// MARK: - ShareSheet helpers

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
