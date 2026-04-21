import SwiftUI
import SwiftData
import FastSharedCore
import UniformTypeIdentifiers
import OSLog

#if canImport(UIKit)
import UIKit
#endif

/// The Hub — HIG-native refactor.
///
/// Uses a native `List` (insetGrouped) so iOS gives us: smooth scrolling,
/// system scroll indicators, native `.swipeActions`, pull-to-refresh,
/// `.searchable` in the nav bar, and accessibility free. Primary "+" CTA
/// lives in the toolbar (trailing) — the Photos/Files/Mail pattern — so
/// nothing floats over the list. Urgency is signalled by a trailing ring
/// + chip, not by tinting whole row backgrounds (which felt loud).
///
/// Bundle-aware: rows check `link.isBundle` and render a stack icon with
/// "N files" subtitle instead of the canonical asset metadata.
struct HistoryView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.clipboard) private var clipboard
    @Environment(\.paywallCoordinator) private var paywallCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)]) private var links: [ShareLinkEntity]

    @State private var viewModel: HistoryViewModel?
    @State private var searchText: String = ""
    @State private var showImporter: Bool = false
    @State private var copyPulseToken: String?
    @State private var revokePulseToken: String?
    #if os(iOS)
    @State private var shareURL: URL?
    #endif

    // Guest-upgrade banner state.
    @State private var guestBannerDismissed: Bool = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)?
        .bool(forKey: "dismissed_guest_hint_v1") ?? false
    @State private var showSignInSheet: Bool = false

    // MARK: - Resolved tokens (semantic, dark-mode-aware)
    // Direto de UIKit — respeita Dark Mode do sistema. FriendlyPalette dark
    // (#0d0625 navy-purple) vazou por esses computed getters; users reclamaram
    // que a Home ficava roxa no dark mode. Agora é .systemBackground / etc.

    private var groundColor: Color { Color(.systemGroupedBackground) }
    private var canvasColor: Color { Color(.systemBackground) }
    private var textColor: Color { Color(.label) }
    private var textDimColor: Color { Color(.secondaryLabel) }
    private var lineColor: Color { Color(.separator) }

    // MARK: - Filtered / snapshot

    private func filtered(_ source: [ShareLinkEntity]) -> [ShareLinkEntity] {
        guard !searchText.isEmpty else { return source }
        let needle = searchText.lowercased()
        return source.filter { link in
            (link.originalFilename ?? "").lowercased().contains(needle) ||
            link.token.lowercased().contains(needle)
        }
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let snapshot = ExpirySnapshot.build(from: filtered(links), now: now)
            rootList(now: now, snapshot: snapshot)
        }
        .foregroundStyle(textColor)
        .navigationTitle("Shares")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search shares")
        .refreshable { await viewModel?.refresh(visibleLinks: links) }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .sensoryFeedback(.success, trigger: copyPulseToken)
        .sensoryFeedback(.impact(weight: .heavy), trigger: revokePulseToken)
        // Programmatic share sheet — fired from the `.swipeActions` "Share"
        // button since ShareLink can't be invoked from a closure.
        .sheet(item: Binding(
            get: { shareURL.map { IdentifiableURL(url: $0) } },
            set: { shareURL = $0?.url }
        )) { wrapped in
            ShareSheet(items: [wrapped.url])
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(for: PersistentIdentifier.self) { id in
            DetailView(linkID: id)
        }
        #endif
        .task {
            if viewModel == nil {
                viewModel = HistoryViewModel(apiClient: apiClient, orchestrator: orchestrator)
            }
            await viewModel?.refresh(visibleLinks: links)
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(onComplete: { showSignInSheet = false })
        }
    }

    // MARK: - Root list

    @ViewBuilder
    private func rootList(now: Date, snapshot: ExpirySnapshot) -> some View {
        if snapshot.activeCount == 0 && searchText.isEmpty {
            emptyStateBody
        } else if snapshot.activeCount == 0 && !searchText.isEmpty {
            searchEmptyBody
        } else {
            List {
                // Guest upgrade banner (dismissible, only for guests)
                if AuthState.currentMode == .guest && !guestBannerDismissed {
                    Section {
                        guestUpgradeBanner
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }

                // Greeting / urgency hint as a compact non-row header.
                if let urgentMessage = urgencyMessage(snapshot: snapshot) {
                    Section {
                        Text(urgentMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                // Grouped sections by urgency tier — lets the native List
                // render section headers HIG-style ("Under 1 hour", etc).
                ForEach(snapshot.grouped, id: \.tier) { group in
                    Section {
                        ForEach(group.links, id: \.token) { link in
                            linkRow(link, now: now)
                        }
                    } header: {
                        Text(group.tier.headline.capitalized)
                            .textCase(nil)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(groundColor)
            #else
            .listStyle(.inset)
            #endif
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func linkRow(_ link: ShareLinkEntity, now: Date) -> some View {
        #if os(iOS)
        NavigationLink(value: link.persistentModelID) {
            NativeLinkRow(link: link, now: now)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await revoke(link) }
            } label: {
                Label("Revoke", systemImage: "xmark.circle")
            }
            Button {
                shareURL = link.shortURL
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                copyLink(link)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.gray)
        }
        .contextMenu {
            Button { copyLink(link) } label: { Label("Copy link", systemImage: "doc.on.doc") }
            ShareLink(item: link.shortURL) { Label("Share…", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) {
                Task { await revoke(link) }
            } label: {
                Label("Revoke", systemImage: "xmark.circle")
            }
        }
        #else
        NativeLinkRow(link: link, now: now)
            .contextMenu {
                Button { copyLink(link) } label: { Label("Copy link", systemImage: "doc.on.doc") }
                Button(role: .destructive) {
                    Task { await revoke(link) }
                } label: {
                    Label("Revoke", systemImage: "xmark.circle")
                }
            }
        #endif
    }

    // MARK: - Toolbar

    #if os(iOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
        // Brand identity in the principal slot — the App Store / iMessage
        // / Instagram pattern. Replaces the plain "Shares" title so the
        // logo is visible on every scroll position.
        ToolbarItem(placement: .principal) {
            BrandLockup(markSize: 22, textSize: 15)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("FastShared")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showImporter = true
            } label: {
                // HIG compose pattern — primary action lives in the nav bar,
                // never floating on top of the list.
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .accessibilityLabel("New share")
        }
    }
    #endif

    // MARK: - Guest banner

    /// Dismissible hint shown to guest-mode users, offering a one-tap
    /// upgrade to Sign in with Apple. Persistence via AppGroup defaults
    /// keeps the dismissal sticky across launches and across extensions.
    private var guestUpgradeBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Syncing is off")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                Text("Sign in with Apple to sync across devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Sign in") { showSignInSheet = true }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Button {
                dismissGuestBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss sign-in hint")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func dismissGuestBanner() {
        guestBannerDismissed = true
        UserDefaults(suiteName: AppGroupPaths.groupIdentifier)?
            .set(true, forKey: "dismissed_guest_hint_v1")
    }

    // MARK: - Empty / search empty

    private var emptyStateBody: some View {
        // iOS 17+ ContentUnavailableView is the HIG-canonical empty state.
        // The CTA lives inline, replacing the old floating gradient button.
        VStack(spacing: 20) {
            ContentUnavailableView {
                Label("No shares yet", systemImage: "paperplane")
            } description: {
                Text("Share a file from any app — FastShared makes a temporary link and copies it to your clipboard.")
            } actions: {
                Button {
                    showImporter = true
                } label: {
                    Text("Share a file")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(groundColor)
    }

    private var searchEmptyBody: some View {
        ContentUnavailableView.search(text: searchText)
            .background(groundColor)
    }

    // MARK: - Urgency message

    /// Returns a plaintext heads-up when at least one row is about to expire.
    /// Rendered as a normal subtitle at the top of the list; replaces the
    /// custom "greeting block" so the nav bar title carries the count.
    private func urgencyMessage(snapshot: ExpirySnapshot) -> String? {
        let urgent = snapshot.grouped.filter { $0.tier <= ExpiryTier.underOneHour }.flatMap(\.links).count
        guard urgent > 0 else { return nil }
        if urgent == 1 {
            return "1 share expires in under an hour."
        }
        return "\(urgent) shares expire in under an hour."
    }

    // MARK: - Actions

    private func copyLink(_ link: ShareLinkEntity) {
        clipboard.copy(link.shortURL.absoluteString)
        copyPulseToken = link.token
    }

    private func revoke(_ link: ShareLinkEntity) async {
        revokePulseToken = link.token
        await viewModel?.revoke(link)
    }

    #if os(iOS)
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let service = uploadService else { return }
        Task(priority: .userInitiated) {
            do {
                // Result is polymorphic (.single / .bundle); Live Activity
                // + history rows carry success visibility, so we discard it.
                _ = try await service.enqueueDrop(urls: urls)
            } catch let gate as SubscriptionGate {
                await MainActor.run { routePaywall(for: gate) }
            } catch let error as APIError {
                if case .paymentRequired(let code, _) = error {
                    await MainActor.run { paywallCoordinator.present(.serverForced(errorCode: code)) }
                }
            } catch {
                Logger(subsystem: "dev.kindrazki.fastshared", category: "upload")
                    .error("handleImport failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func routePaywall(for gate: SubscriptionGate) {
        switch gate {
        case .dailyCapReached(let used, let cap):
            paywallCoordinator.present(.dailyCapReached(used: used, cap: cap))
        case .fileTooLarge(let size, _):
            paywallCoordinator.present(.largeFileRequested(sizeBytes: size))
        case .retentionTooLong(let seconds, _):
            let policy: RetentionPolicy = {
                switch seconds {
                case 0...3600: return .oneHour
                case 0...86_400: return .oneDay
                case 0...604_800: return .oneWeek
                default: return .oneMonth
                }
            }()
            paywallCoordinator.present(.longRetentionRequested(policy: policy))
        case .cloudSyncRequiresPro:
            paywallCoordinator.present(.cloudSyncRequested)
        }
    }
    #endif
}

// MARK: - NativeLinkRow

/// HIG-native row: leading icon (mime glyph or bundle stack), title,
/// metadata subtitle, trailing ring + countdown. No card chrome — the
/// `List` row supplies the background/separator. Urgency signalled by
/// the ring color + optional chip, not by full-row tinting.
struct NativeLinkRow: View {
    let link: ShareLinkEntity
    let now: Date

    private var remaining: TimeInterval { max(0, link.expiresAt.timeIntervalSince(now)) }
    private var retention: TimeInterval { max(0, link.expiresAt.timeIntervalSince(link.createdAt)) }
    private var progress: Double { retention > 0 ? max(0, min(1, remaining / retention)) : 0 }
    private var tier: ExpiryTier { ExpiryTier.tier(for: remaining) }
    private var isUrgent: Bool { tier <= ExpiryTier.underOneHour }

    // Bundle = stacked-doc icon + "N files"; single = mime glyph + filename.
    private var isBundle: Bool { link.isBundle }
    private var bundleCount: Int { link.bundledAssets.count }

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(.body)
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    if isUrgent {
                        urgencyChip
                    }
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                UrgencyRing(progress: progress, size: 26, stroke: 3)
                Text(ExpiryFormatter.remaining(remaining))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(tier.urgencyColor)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Leading icon

    @ViewBuilder
    private var leadingIcon: some View {
        if isBundle {
            // Stacked-doc glyph for bundle rows — HIG metaphor for
            // "multiple items". Tile chrome matches FileGlyph so rows
            // line up visually regardless of kind.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        } else {
            FileGlyph(contentType: link.contentType, size: 36)
        }
    }

    // MARK: - Text

    private var titleText: String {
        if isBundle {
            let n = max(bundleCount, 1)
            return n == 1 ? "1 file" : "\(n) files"
        }
        return link.originalFilename ?? link.token
    }

    private var subtitleText: String {
        let size = ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file)
        let ago = ExpiryFormatter.createdAgo(link.createdAt, now: now)
        return "\(size) · \(ago)"
    }

    // MARK: - Urgency chip

    private var urgencyChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tier.urgencyColor)
                .frame(width: 5, height: 5)
            Text(tier.urgencyLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tier.urgencyColor)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tier.urgencyColor.opacity(0.12))
        )
    }
}

#if os(iOS)
// MARK: - ShareSheet helpers

/// Tiny wrapper so a `URL` can drive `.sheet(item:)` (Identifiable).
private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// SwiftUI wrapper for `UIActivityViewController`. Used when a `ShareLink`
/// button is not an option — e.g. firing the share sheet from inside our
/// swipe-action callback, where we are outside the button chain.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
