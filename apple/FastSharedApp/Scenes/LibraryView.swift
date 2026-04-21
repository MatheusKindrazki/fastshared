import SwiftUI
import SwiftData
import FastSharedCore
import UniformTypeIdentifiers
import OSLog

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Sidebar selection

/// Library sidebar filters. Separate from the legacy `MacSidebarSelection`
/// (which covered "all / ending soon / this week / expired") because the
/// redesign's sidebar talks in user-facing categories rather than expiry
/// buckets.
enum LibrarySelection: Hashable, CaseIterable, Identifiable {
    case library
    case screenshots
    case sentToday
    case expiringSoon

    var id: Self { self }

    var label: String {
        switch self {
        case .library:      return "Library"
        case .screenshots:  return "Screenshots"
        case .sentToday:    return "Sent today"
        case .expiringSoon: return "Expiring soon"
        }
    }
}

// MARK: - LibraryView

/// Split-view Library for iPad (regular) + macOS. Dense table, cream ground,
/// amber/violet tokens — matches the `fastshared — Library` prototype.
///
/// Shares the same SwiftData container as the iPhone `HistoryView`; we reuse
/// `HistoryViewModel` for refresh/revoke so the underlying orchestrator
/// behaviour stays identical across surfaces. Heavy UI lives in a couple of
/// private structs at the bottom of the file.
struct LibraryView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.clipboard) private var clipboard
    @Environment(\.paywallCoordinator) private var paywallCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)])
    private var allLinks: [ShareLinkEntity]

    @State private var viewModel: HistoryViewModel?
    @State private var selection: LibrarySelection = .library
    @State private var searchText: String = ""
    @State private var showFileImporter: Bool = false
    @State private var isDragTargeted: Bool = false
    #if os(iOS)
    @State private var shareURL: URL?
    #endif

    // MARK: - Palette resolution
    // Light: Friendly cream branded Hub (intentional, matches protótipo).
    // Dark: semantic system — FriendlyPalette dark é navy-purple (#0d0625)
    // que vazou como "Purple background" nos prints dos users. Em dark, vamos
    // de systemBackground para parecer Mail/Photos.

    private var groundColor: Color {
        colorScheme == .dark ? Color(.systemGroupedBackground) : BrandPalette.friendlyGround
    }
    private var paperColor: Color {
        colorScheme == .dark ? Color(.systemBackground) : BrandPalette.friendlyCanvas
    }
    private var surfaceColor: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : BrandPalette.friendlySurface0
    }
    private var textColor: Color {
        colorScheme == .dark ? Color(.label) : BrandPalette.friendlyText
    }
    private var textDimColor: Color {
        colorScheme == .dark ? Color(.secondaryLabel) : BrandPalette.friendlyTextDim
    }
    private var textFaintColor: Color {
        colorScheme == .dark ? Color(.tertiaryLabel) : BrandPalette.friendlyTextFaint
    }
    private var lineColor: Color {
        colorScheme == .dark ? Color(.separator) : BrandPalette.friendlyLine
    }

    // MARK: - Filtered snapshots

    private func filtered(_ links: [ShareLinkEntity], now: Date) -> [ShareLinkEntity] {
        let base: [ShareLinkEntity]
        switch selection {
        case .library:
            base = links.filter { $0.linkStatus == LinkStatus.active.rawValue && $0.expiresAt > now }
        case .screenshots:
            base = links.filter {
                $0.linkStatus == LinkStatus.active.rawValue
                    && $0.expiresAt > now
                    && ($0.contentType.hasPrefix("image/")
                        || ($0.originalFilename ?? "").lowercased().contains("screenshot"))
            }
        case .sentToday:
            let startOfDay = Calendar.current.startOfDay(for: now)
            base = links.filter { $0.createdAt >= startOfDay && $0.expiresAt > now }
        case .expiringSoon:
            base = links.filter {
                let r = $0.expiresAt.timeIntervalSince(now)
                let tier = ExpiryTier.tier(for: r)
                return $0.linkStatus == LinkStatus.active.rawValue
                    && $0.expiresAt > now
                    && tier <= ExpiryTier.underOneDay
            }
        }
        guard !searchText.isEmpty else { return base }
        let needle = searchText.lowercased()
        return base.filter { link in
            (link.originalFilename ?? "").lowercased().contains(needle)
                || link.token.lowercased().contains(needle)
                || link.shortURLString.lowercased().contains(needle)
        }
    }

    // MARK: - Counts (for sidebar badges) — always against active universe

    private var activeLinks: [ShareLinkEntity] {
        allLinks.filter { $0.linkStatus == LinkStatus.active.rawValue && $0.expiresAt > Date() }
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                selection: $selection,
                activeCount: activeLinks.count,
                textColor: textColor,
                textDimColor: textDimColor,
                textFaintColor: textFaintColor,
                lineColor: lineColor,
                surfaceColor: surfaceColor
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            #if os(macOS)
            .background(surfaceColor)
            #endif
        } detail: {
            detailColumn
                #if os(macOS)
                .background(groundColor)
                #endif
        }
        .navigationSplitViewStyle(.balanced)
        .tint(BrandPalette.accent.hot)
        .task {
            if viewModel == nil {
                viewModel = HistoryViewModel(apiClient: apiClient, orchestrator: orchestrator)
            }
            await viewModel?.refresh(visibleLinks: allLinks)
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        #if os(iOS)
        .sheet(item: Binding(
            get: { shareURL.map { IdentifiableURLLib(url: $0) } },
            set: { shareURL = $0?.url }
        )) { wrapped in
            LibraryShareSheet(items: [wrapped.url])
                .presentationDetents([.medium, .large])
        }
        #endif
    }

    // MARK: - Detail column

    private var detailColumn: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let rows = filtered(allLinks, now: now)
            LibraryDetail(
                title: titleText(count: rows.count),
                nextExpiryLabel: nextExpiryLabel(rows: rows, now: now),
                rows: rows,
                now: now,
                searchText: $searchText,
                onDropFile: { showFileImporter = true },
                onCopy: { copyLink($0) },
                onRevoke: { link in Task { await viewModel?.revoke(link) } },
                onShare: { link in shareOrOpen(link) },
                onRowOpen: { _ in },
                groundColor: groundColor,
                paperColor: paperColor,
                textColor: textColor,
                textDimColor: textDimColor,
                textFaintColor: textFaintColor,
                lineColor: lineColor
            )
            .onDrop(of: [UTType.fileURL, UTType.item], isTargeted: $isDragTargeted) { providers in
                handleDropProviders(providers)
                return true
            }
            .overlay(alignment: .center) {
                if isDragTargeted {
                    DropOverlay()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        }
    }

    // MARK: - Dynamic strings

    private func titleText(count: Int) -> String {
        switch selection {
        case .library:
            return count == 1 ? "1 active link" : "\(count) active links"
        case .screenshots:
            return count == 1 ? "1 screenshot" : "\(count) screenshots"
        case .sentToday:
            return count == 1 ? "1 sent today" : "\(count) sent today"
        case .expiringSoon:
            return count == 1 ? "1 expiring soon" : "\(count) expiring soon"
        }
    }

    /// Amber overline — "NEXT TO EXPIRE · 40S". Nil when no rows or when every
    /// row has >24h left (calm state).
    private func nextExpiryLabel(rows: [ShareLinkEntity], now: Date) -> String? {
        guard let nearest = rows.map(\.expiresAt).min() else { return nil }
        let remaining = nearest.timeIntervalSince(now)
        guard remaining > 0, remaining <= 24 * 3600 else { return nil }
        let human = ExpiryFormatter.remaining(remaining).uppercased()
        return "NEXT TO EXPIRE · \(human)"
    }

    // MARK: - Actions

    private func copyLink(_ link: ShareLinkEntity) {
        clipboard.copy(link.shortURLString)
    }

    /// Per-platform share dispatch. iOS pops `UIActivityViewController`; macOS
    /// hands the URL straight to the system browser since AppKit has no in-app
    /// share sheet equivalent for links.
    private func shareOrOpen(_ link: ShareLinkEntity) {
        #if os(iOS)
        shareURL = link.shortURL
        #else
        NSWorkspace.shared.open(link.shortURL)
        #endif
    }

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
                Logger(subsystem: "dev.kindrazki.fastshared", category: "upload")
                    .error("LibraryView import failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) {
        guard let service = uploadService else { return }
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            do {
                _ = try await service.enqueueDrop(urls: urls)
            } catch let gate as SubscriptionGate {
                await MainActor.run { routePaywall(for: gate) }
            } catch {
                Logger(subsystem: "dev.kindrazki.fastshared", category: "upload")
                    .error("LibraryView drop failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
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
}

// MARK: - LibrarySidebar

private struct LibrarySidebar: View {
    @Binding var selection: LibrarySelection
    let activeCount: Int
    let textColor: Color
    let textDimColor: Color
    let textFaintColor: Color
    let lineColor: Color
    let surfaceColor: Color

    // WHY: iOS `List(selection:)` only takes an Optional binding for the row
    // tag. We bridge a non-optional `LibrarySelection` here so the parent can
    // keep its API simple while the underlying List honours its requirement.
    private var optionalBinding: Binding<LibrarySelection?> {
        Binding(get: { selection }, set: { newValue in
            if let v = newValue { selection = v }
        })
    }

    var body: some View {
        List(selection: optionalBinding) {
            // Brand header — no section so it sits flush at the top.
            Section {
                BrandLockup(markSize: 18, textSize: 14)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }

            // Main filters — bullet dots mimic the protótipo list style.
            Section {
                ForEach(LibrarySelection.allCases) { item in
                    sidebarRow(item)
                        .tag(item)
                }
            }

            // Footer device card. Plain section header in mono caps.
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ios · mac")
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(textColor)
                    Text("····\(deviceShortHash)")
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(textFaintColor)
                }
                .padding(.vertical, 2)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("DEVICE")
                    .font(.system(size: 10, weight: .semibold).monospaced())
                    .tracking(0.08 * 10)
                    .foregroundStyle(textFaintColor)
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(surfaceColor)
        #else
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(surfaceColor)
        #endif
    }

    @ViewBuilder
    private func sidebarRow(_ item: LibrarySelection) -> some View {
        let isActive = selection == item
        HStack(spacing: 8) {
            Text("•")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? BrandPalette.accent.hot : textDimColor)
            Text(item.label)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? BrandPalette.accent.hot : textColor)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    /// Pseudo device hash — the mock shows `····6a2f`. We derive a stable 4-char
    /// suffix from the process identifier + host name so every device gets a
    /// different tail without reaching into keychain on every render. Good
    /// enough for a visual affordance; a future pass can wire it to the real
    /// `DeviceTokenStore.deviceId`.
    private var deviceShortHash: String {
        #if os(macOS)
        let raw = Host.current().localizedName ?? "mac"
        #else
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? "ios"
        #endif
        let digest = abs(raw.hashValue)
        return String(format: "%04x", digest & 0xffff)
    }
}

// MARK: - LibraryDetail

private struct LibraryDetail: View {
    let title: String
    let nextExpiryLabel: String?
    let rows: [ShareLinkEntity]
    let now: Date
    @Binding var searchText: String

    let onDropFile: () -> Void
    let onCopy: (ShareLinkEntity) -> Void
    let onRevoke: (ShareLinkEntity) -> Void
    let onShare: (ShareLinkEntity) -> Void
    let onRowOpen: (ShareLinkEntity) -> Void

    let groundColor: Color
    let paperColor: Color
    let textColor: Color
    let textDimColor: Color
    let textFaintColor: Color
    let lineColor: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 24)

                tableBlock
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(groundColor)
        #if os(iOS)
        .searchable(text: $searchText, placement: .automatic, prompt: "Search shares")
        #endif
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label = nextExpiryLabel {
                Text(label)
                    .font(.system(size: 11, weight: .bold).monospaced())
                    .tracking(0.08 * 11)
                    .foregroundStyle(BrandPalette.accentHot)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.02 * 32)
                    .foregroundStyle(textColor)

                Spacer(minLength: 16)

                Button(action: onDropFile) {
                    Text("+ DROP FILE")
                        .font(.system(size: 11, weight: .bold).monospaced())
                        .tracking(0.06 * 11)
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BrandPalette.accent.hot)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Drop file")
            }
        }
    }

    // MARK: - Table block

    @ViewBuilder
    private var tableBlock: some View {
        VStack(spacing: 0) {
            // Column headers row (sticky top of the card).
            HStack(spacing: 0) {
                headerCell("FILE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                headerCell("SIZE")
                    .frame(width: 90, alignment: .leading)
                headerCell("LINK")
                    .frame(width: 170, alignment: .leading)
                headerCell("EXPIRES")
                    .frame(width: 110, alignment: .leading)
                Color.clear.frame(width: 34)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(paperColor.opacity(0.6))

            Divider().overlay(lineColor)

            if rows.isEmpty {
                emptyCard
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.token) { index, link in
                        if index > 0 {
                            Divider().overlay(lineColor.opacity(0.7))
                        }
                        LibraryRow(
                            link: link,
                            now: now,
                            textColor: textColor,
                            textDimColor: textDimColor,
                            textFaintColor: textFaintColor,
                            onCopy: { onCopy(link) },
                            onRevoke: { onRevoke(link) },
                            onShare: { onShare(link) }
                        )
                    }
                }
            }
        }
        .background(paperColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(lineColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func headerCell(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .bold).monospaced())
            .tracking(0.08 * 10)
            .foregroundStyle(textFaintColor)
    }

    @ViewBuilder
    private var emptyCard: some View {
        VStack(spacing: 10) {
            PlaneArcMark(size: 44)
                .opacity(0.5)
            Text("Nothing here yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textDimColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - LibraryRow

private struct LibraryRow: View {
    let link: ShareLinkEntity
    let now: Date
    let textColor: Color
    let textDimColor: Color
    let textFaintColor: Color

    let onCopy: () -> Void
    let onRevoke: () -> Void
    let onShare: () -> Void

    @State private var copyFlash = false

    private var remaining: TimeInterval { max(0, link.expiresAt.timeIntervalSince(now)) }
    private var retention: TimeInterval { max(0, link.expiresAt.timeIntervalSince(link.createdAt)) }
    private var progress: Double { retention > 0 ? max(0, min(1, remaining / retention)) : 0 }
    private var tier: ExpiryTier { ExpiryTier.tier(for: remaining) }

    var body: some View {
        HStack(spacing: 0) {
            // FILE column — leading urgency strip + glyph + filename.
            HStack(spacing: 10) {
                Rectangle()
                    .fill(tier.urgencyColor)
                    .frame(width: 3, height: 36)
                    .clipShape(Capsule())

                leadingGlyph
                    .frame(width: 26, height: 26)

                Text(filename)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // SIZE
            Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(textDimColor)
                .frame(width: 90, alignment: .leading)

            // LINK (tap-to-copy). Violet accent per mockup.
            Button {
                onCopy()
                withAnimation(.easeOut(duration: 0.1)) { copyFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.3)) { copyFlash = false }
                }
            } label: {
                Text(shortPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(copyFlash ? BrandPalette.accent.hot.opacity(0.55) : BrandPalette.accent.hot)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 160, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Copy link")
            .frame(width: 170, alignment: .leading)

            // EXPIRES — ring + countdown.
            HStack(spacing: 6) {
                UrgencyRing(progress: progress, size: 16, stroke: 2)
                Text(ExpiryFormatter.remaining(remaining))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tier.urgencyColor)
            }
            .frame(width: 110, alignment: .leading)

            // Options menu (⋮).
            Menu {
                Button { onCopy() } label: { Label("Copy link", systemImage: "doc.on.doc") }
                Button { onShare() } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                Divider()
                Button(role: .destructive) { onRevoke() } label: {
                    Label("Revoke", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .foregroundStyle(textFaintColor)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 34)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contextMenu {
            Button { onCopy() } label: { Label("Copy link", systemImage: "doc.on.doc") }
            Button { onShare() } label: { Label("Share…", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { onRevoke() } label: {
                Label("Revoke", systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if link.isBundle {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(BrandPalette.accentHot.opacity(0.14))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrandPalette.accentHot)
            }
        } else {
            FileGlyph(contentType: link.contentType, size: 26)
        }
    }

    private var filename: String {
        if link.isBundle {
            let n = max(link.bundledAssets.count, 1)
            return n == 1 ? "1 file" : "\(n) files"
        }
        return link.originalFilename ?? link.token
    }

    /// Renders `/s/{token}` even if the server ships a longer short URL.
    /// Keeps the column width stable and matches the prototype visual.
    private var shortPath: String {
        let token = link.token
        return "/s/\(token)"
    }
}

// MARK: - Drop overlay

private struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(BrandPalette.accent.hot)
                Text("Drop to share")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrandPalette.accent.hot)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BrandPalette.accent.hot, style: StrokeStyle(lineWidth: 2, dash: [6]))
            )
        }
    }
}

// MARK: - iOS share-sheet plumbing (local helpers — HistoryView has its own copies)

#if os(iOS)
private struct IdentifiableURLLib: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct LibraryShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
