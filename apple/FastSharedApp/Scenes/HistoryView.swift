import SwiftUI
import SwiftData
import FastSharedCore
import UniformTypeIdentifiers
import OSLog

#if canImport(UIKit)
import UIKit
#endif

/// The Hub — "Friendly" redesign v2.
///
/// Composition (top → bottom):
///  - Header: BrandLockup + gear icon
///  - Greeting block: dynamic count headline + optional urgency subtitle
///  - Empty state (when no active shares): mark + copy + hint card + CTA
///  - Share list: LazyVStack of urgency-aware card rows
///  - Footer CTA gradient with "Share something new +" button
///
/// Driven by a `TimelineView` tick (once per second) so countdowns stay live
/// and rows reshuffle between urgency sections as they decay.
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
    // Coordinator for the custom swipe-to-reveal cards below. Lives on the
    // view so scrolling away / refiltering resets it naturally.
    @State private var swipeManager = SwipeableCardManager()
    #if os(iOS)
    @State private var shareURL: URL?
    #endif

    // Guest-upgrade banner state.
    @State private var guestBannerDismissed: Bool = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)?
        .bool(forKey: "dismissed_guest_hint_v1") ?? false
    @State private var showSignInSheet: Bool = false

    // MARK: - Resolved tokens (light/dark adaptive)

    private var groundColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyGroundDark : BrandPalette.friendlyGround
    }
    private var canvasColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyCanvasDark : BrandPalette.friendlyCanvas
    }
    private var surface0Color: Color {
        colorScheme == .dark ? BrandPalette.friendlySurface0Dark : BrandPalette.friendlySurface0
    }
    private var textColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyTextDark : BrandPalette.friendlyText
    }
    private var textDimColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyTextDimDark : BrandPalette.friendlyTextDim
    }
    private var textFaintColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyTextFaintDark : BrandPalette.friendlyTextFaint
    }
    private var lineColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyLineDark : BrandPalette.friendlyLine
    }

    // MARK: - Filtered links

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
        ZStack {
            groundColor.ignoresSafeArea(.all)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let now = timeline.date
                let snapshot = ExpirySnapshot.build(from: filtered(links), now: now)
                mainContent(now: now, snapshot: snapshot)
            }
        }
        .foregroundStyle(textColor)
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(groundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        .refreshable {
            await viewModel?.refresh(visibleLinks: links)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .sensoryFeedback(.success, trigger: copyPulseToken)
        .sensoryFeedback(.impact(weight: .heavy), trigger: revokePulseToken)
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
        #if os(iOS)
        // WHY: the swipe-reveal "Share" action needs to programmatically
        // present the system share sheet (a native ShareLink button can't be
        // fired from inside our custom SwipeAction callback). Toggling
        // `shareURL` drives a .sheet — set to nil when dismissed.
        .sheet(item: Binding(
            get: { shareURL.map { IdentifiableURL(url: $0) } },
            set: { shareURL = $0?.url }
        )) { wrapped in
            ShareSheet(items: [wrapped.url])
                .presentationDetents([.medium, .large])
        }
        #endif
        #if os(iOS)
        .navigationDestination(for: PersistentIdentifier.self) { id in
            DetailView(linkID: id)
        }
        #endif
    }

    // MARK: - Main content

    @ViewBuilder
    private func mainContent(now: Date, snapshot: ExpirySnapshot) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    // Header
                    headerRow
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)

                    // Guest upgrade banner (dismissible, only for guests)
                    if AuthState.currentMode == .guest && !guestBannerDismissed {
                        guestUpgradeBanner
                            .padding(.horizontal, 24)
                            .padding(.bottom, 14)
                    }

                    // Greeting
                    greetingBlock(snapshot: snapshot)
                        .padding(.top, 4)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 14)

                    if snapshot.activeCount == 0 && searchText.isEmpty {
                        // Empty state (owns its own CTA — footer CTA hidden below)
                        emptyState
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    } else if snapshot.activeCount == 0 && !searchText.isEmpty {
                        // Search empty
                        searchEmptyState
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    } else {
                        // Share list
                        shareList(snapshot: snapshot, now: now)
                    }

                    // Bottom spacer for the gradient footer CTA. Not needed on
                    // the empty state since its own CTA is rendered inline.
                    if snapshot.activeCount > 0 {
                        Color.clear.frame(height: 120)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)

            // Gradient footer CTA — only when the list has items. On the empty
            // state we rely on the inline "Share a file" button so the user
            // isn't choosing between two identical CTAs.
            if snapshot.activeCount > 0 {
                footerCTA
            }
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 10) {
            BrandLockup(markSize: 28, textSize: 19)

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                ZStack {
                    Circle()
                        .fill(canvasColor)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(lineColor, lineWidth: 1)
                        )
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(textDimColor)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Guest upgrade banner

    /// Dismissible hint shown to guest-mode users, offering a one-tap
    /// upgrade to Sign in with Apple. Persistence via AppGroup defaults
    /// keeps the dismissal sticky across launches and across extensions.
    private var guestUpgradeBanner: some View {
        let bgTint: Color = colorScheme == .dark
            ? BrandPalette.accentHot.opacity(0.18)
            : BrandPalette.accentHot.opacity(0.09)
        let borderTint: Color = BrandPalette.accentHot.opacity(0.22)

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrandPalette.accentHot)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("Syncing is off")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor)
                Text("Sign in with Apple to sync across your devices.")
                    .font(.system(size: 11))
                    .foregroundStyle(textDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    showSignInSheet = true
                } label: {
                    Text("Sign in")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BrandPalette.accentHot)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign in with Apple")

                Button {
                    dismissGuestBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textDimColor)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss sign-in hint")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(bgTint)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(borderTint, lineWidth: 1)
                )
        )
    }

    private func dismissGuestBanner() {
        guestBannerDismissed = true
        UserDefaults(suiteName: AppGroupPaths.groupIdentifier)?
            .set(true, forKey: "dismissed_guest_hint_v1")
    }

    // MARK: - Greeting block

    private func greetingBlock(snapshot: ExpirySnapshot) -> some View {
        let count = snapshot.activeCount
        // Urgency: links expiring under 1 hour
        let urgentCount = snapshot.grouped.filter { $0.tier <= ExpiryTier.underOneHour }.flatMap(\.links).count

        return VStack(alignment: .leading, spacing: 6) {
            Text("\(count) link\(count == 1 ? "" : "s") live right now")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.025 * 28)
                .lineSpacing(1.15)
                .foregroundStyle(textColor)

            if urgentCount > 0 {
                Text("One expires in under an hour — tap to extend or stop sharing.")
                    .font(.system(size: 14))
                    .foregroundStyle(textDimColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            PlaneArcMark(size: 120, ambient: true)
                .accessibilityHidden(true)
                .padding(.top, 24)

            VStack(spacing: 10) {
                Text("Ready when you are.")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)

                Text("Share a file from any app — FastShared creates a temporary link and copies it to your clipboard.")
                    .font(.system(size: 15))
                    .foregroundStyle(textDimColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            // Hint card
            HStack(spacing: 8) {
                Text("💡")
                    .font(.system(size: 16))
                Text("Try the share sheet in Photos — pick FastShared.")
                    .font(.system(size: 13))
                    .foregroundStyle(textDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canvasColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(lineColor, lineWidth: 1)
                    )
            )

            Button {
                showImporter = true
            } label: {
                Text("Share a file")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(BrandPalette.accentHot)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search empty state

    private var searchEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No results")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(textColor)
            Text("Nothing matches \"\(searchText)\".")
                .font(.system(size: 15))
                .foregroundStyle(textDimColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    // MARK: - Share list

    @ViewBuilder
    private func shareList(snapshot: ExpirySnapshot, now: Date) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(snapshot.grouped.flatMap(\.links), id: \.token) { link in
                // WHY: `.swipeActions(...)` only fires inside a `List`; our
                // LazyVStack layout needs a hand-rolled reveal. The manager
                // keeps at-most-one row open at a time across the whole list.
                SwipeableCardManaged(id: link.token, manager: swipeManager) {
                    NavigationLink(value: link.persistentModelID) {
                        FriendlyLinkCard(link: link, now: now, colorScheme: colorScheme)
                    }
                    .buttonStyle(.plain)
                } actions: {
                    SwipeAction(
                        label: "Share",
                        systemImage: "square.and.arrow.up",
                        tint: BrandPalette.accentHot
                    ) {
                        #if os(iOS)
                        shareURL = link.shortURL
                        #endif
                    }
                    SwipeAction(
                        label: "Revoke",
                        systemImage: "xmark.circle",
                        tint: BrandPalette.urgencyCritical,
                        isDestructive: true
                    ) {
                        Task { await revoke(link) }
                    }
                }
                .padding(.bottom, 10)
                .contextMenu {
                    Button {
                        copyLink(link)
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                    }
                    #if os(iOS)
                    ShareLink(item: link.shortURL) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    #endif
                    Button(role: .destructive) {
                        Task { await revoke(link) }
                    } label: {
                        Label("Revoke", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Footer CTA

    private var footerCTA: some View {
        VStack(spacing: 0) {
            // Gradient fade overlay
            LinearGradient(
                stops: [
                    .init(color: groundColor.opacity(0), location: 0),
                    .init(color: groundColor.opacity(0.6), location: 0.4),
                    .init(color: groundColor, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            // Button area on solid ground
            groundColor
                .overlay(alignment: .center) {
                    Button {
                        showImporter = true
                    } label: {
                        Text("Share something new +")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 24)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(BrandPalette.accentHot)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                }
                .frame(height: 72)
        }
        .padding(.bottom, 28)
        .ignoresSafeArea(edges: .bottom)
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
                _ = try await service.enqueueDrop(urls: urls)
            } catch let gate as SubscriptionGate {
                await MainActor.run { routePaywall(for: gate) }
            } catch let error as APIError {
                if case .paymentRequired(let code, _) = error {
                    await MainActor.run { paywallCoordinator.present(.serverForced(errorCode: code)) }
                }
            } catch {
                // Surface via Logger so TestFlight failures aren't invisible.
                // Live Activity / toast handles success visibility; only the
                // typed Subscription/Payment paths above have bespoke UI.
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

// MARK: - FriendlyLinkCard

/// One row in the share list — "Friendly" redesign v2.
///
/// An urgency-aware card with a FileTile, filename + meta, and a trailing
/// Ring + compact remaining-time label. Urgent rows (< 1 day) get a tinted
/// background and colored border.
struct FriendlyLinkCard: View {
    let link: ShareLinkEntity
    let now: Date
    let colorScheme: ColorScheme

    // MARK: - Derived values

    private var remaining: TimeInterval { max(0, link.expiresAt.timeIntervalSince(now)) }
    private var retention: TimeInterval { max(0, link.expiresAt.timeIntervalSince(link.createdAt)) }
    private var progress: Double { retention > 0 ? max(0, min(1, remaining / retention)) : 0 }
    private var tier: ExpiryTier { ExpiryTier.tier(for: remaining) }

    private var isUrgent: Bool {
        tier <= ExpiryTier.underOneDay
    }

    // MARK: - Adaptive tokens

    private var canvasColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyCanvasDark : BrandPalette.friendlyCanvas
    }
    private var textColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyTextDark : BrandPalette.friendlyText
    }
    private var textDimColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyTextDimDark : BrandPalette.friendlyTextDim
    }
    private var lineColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyLineDark : BrandPalette.friendlyLine
    }

    private var urgencyColor: Color { tier.urgencyColor }
    private var cardBg: Color {
        if isUrgent {
            return colorScheme == .dark ? tier.urgencyBgDark : tier.urgencyBgLight
        }
        return canvasColor
    }
    private var cardBorder: Color {
        isUrgent ? urgencyColor.opacity(0.21) : lineColor
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // File type tile
            FileGlyph(contentType: link.contentType, size: 44)

            // Filename + meta
            VStack(alignment: .leading, spacing: 4) {
                Text(link.originalFilename ?? link.token)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    // Urgency chip (critical or warning tiers)
                    if tier <= ExpiryTier.underOneDay {
                        urgencyChip
                    }

                    Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                        .font(.system(size: 12))
                        .foregroundStyle(textDimColor)

                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(textDimColor)

                    Text(ExpiryFormatter.createdAgo(link.createdAt, now: now))
                        .font(.system(size: 12))
                        .foregroundStyle(textDimColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Ring + time remaining
            VStack(alignment: .trailing, spacing: 4) {
                UrgencyRing(progress: progress, size: 38, stroke: 3.5)
                Text(ExpiryFormatter.remaining(remaining))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(urgencyColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Urgency chip

    private var urgencyChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(urgencyColor)
                .frame(width: 6, height: 6)
            Text(tier.urgencyLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(urgencyColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .background(
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? tier.urgencyBgDark : tier.urgencyBgLight)
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
/// SwipeAction callback, where we are outside the button chain.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
