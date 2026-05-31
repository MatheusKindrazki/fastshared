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
/// (expiry-bucket model) — the redesign talks user categories.
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

    var symbol: String {
        switch self {
        case .library:      return "tray.full"
        case .screenshots:  return "photo.on.rectangle"
        case .sentToday:    return "paperplane"
        case .expiringSoon: return "hourglass"
        }
    }
}

// MARK: - LibraryView

/// Split-view Library for iPad (regular) + macOS. Matches the `Library`
/// protótipo but respects native HIG weight on macOS (dark mode goes
/// semantic, light mode keeps Friendly cream).
struct LibraryView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.clipboard) private var clipboard
    @Environment(\.paywallCoordinator) private var paywallCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)])
    private var allLinks: [ShareLinkEntity]

    @Query(sort: [SortDescriptor(\DeviceEntity.lastSeenAt, order: .reverse)])
    private var devices: [DeviceEntity]

    @State private var viewModel: HistoryViewModel?
    @State private var selection: LibrarySelection = .library
    @State private var searchText: String = ""
    @State private var showFileImporter: Bool = false
    @State private var isDragTargeted: Bool = false
    #if os(iOS)
    @State private var shareURL: URL?
    #endif

    // MARK: - Palette resolution
    // Light: Friendly cream (brand Hub intent).
    // Dark: semantic NSColor/UIColor — avoids the #0d0625 navy-purple leak.

    private var groundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        colorScheme == .dark ? Color.sysGroupedBackground : BrandPalette.friendlyGround
        #endif
    }
    private var paperColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        colorScheme == .dark ? Color.sysBackground : BrandPalette.friendlyCanvas
        #endif
    }
    private var surfaceColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        colorScheme == .dark ? Color.sysSecondaryBackground : BrandPalette.friendlySurface0
        #endif
    }
    private var textColor: Color {
        #if os(macOS)
        Color(nsColor: .labelColor)
        #else
        colorScheme == .dark ? Color.sysLabel : BrandPalette.friendlyText
        #endif
    }
    private var textDimColor: Color {
        #if os(macOS)
        Color(nsColor: .secondaryLabelColor)
        #else
        colorScheme == .dark ? Color.sysSecondaryLabel : BrandPalette.friendlyTextDim
        #endif
    }
    private var textFaintColor: Color {
        #if os(macOS)
        Color(nsColor: .tertiaryLabelColor)
        #else
        colorScheme == .dark ? Color.sysTertiaryLabel : BrandPalette.friendlyTextFaint
        #endif
    }
    private var lineColor: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        colorScheme == .dark ? Color.sysSeparator : BrandPalette.friendlyLine
        #endif
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

    // MARK: - Counts (sidebar badges, always active universe)

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
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
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
                subtitle: subtitleText(count: rows.count),
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
            // WHY: attach onDrop to the whole detail column — SwiftUI on macOS
            // drops the target hit box if the inner ScrollView is empty (no
            // content means no hit target); anchoring here guarantees the drop
            // always fires. The overlay gives visual feedback.
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

    private func subtitleText(count: Int) -> String {
        switch selection {
        case .library:      return "Your shares across every device"
        case .screenshots:  return "Quick screen grabs you sent"
        case .sentToday:    return "Everything that went out today"
        case .expiringSoon: return "Less than 24 hours left"
        }
    }

    /// Violet overline — "NEXT TO EXPIRE · 40S". Nil when calm (>24h).
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

    /// Per-platform share: iOS pops activity sheet; macOS opens the link.
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
        guard let service = uploadService else {
            Logger(subsystem: "dev.kindrazki.fastshared", category: "upload")
                .error("LibraryView drop: uploadService missing in environment")
            return
        }
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else {
                Logger(subsystem: "dev.kindrazki.fastshared", category: "upload")
                    .error("LibraryView drop: no URLs resolved from \(providers.count, privacy: .public) provider(s)")
                return
            }
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
                case 0...60: return .oneMinute
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
    @State private var showSettings = false

    private let deviceVisibilityWindow: TimeInterval = 30 * 24 * 60 * 60  // 30 days

    @Query(sort: [SortDescriptor(\DeviceEntity.lastSeenAt, order: .reverse)])
    private var devices: [DeviceEntity]

    // WHY: iOS `List(selection:)` takes an Optional binding. We bridge the
    // non-optional LibrarySelection here so the parent stays simple.
    private var optionalBinding: Binding<LibrarySelection?> {
        Binding(get: { selection }, set: { newValue in
            if let v = newValue { selection = v }
        })
    }

    var body: some View {
        List(selection: optionalBinding) {
            // Brand header — flush at the top.
            Section {
                BrandLockup(markSize: 22, textSize: 17)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }

            // Main filters with symbol glyphs.
            Section {
                ForEach(LibrarySelection.allCases) { item in
                    sidebarRow(item)
                        .tag(item)
                }
            }

            // Device footer. Lists every device on the iCloud account (synced
            // via CloudKit DeviceRecord); falls back to a single local row when
            // sync hasn't populated yet.
            Section {
                if visibleDevices.isEmpty {
                    deviceRow(name: deviceName, platform: localPlatform, isLocal: true)
                } else {
                    ForEach(visibleDevices) { device in
                        deviceRow(name: device.name.isEmpty ? deviceName : device.name,
                                  platform: device.platform,
                                  isLocal: device.deviceId == localDeviceId)
                    }
                }
            } header: {
                Text(visibleDevices.count > 1 ? "DEVICES" : "DEVICE")
                    .font(.system(size: 11, weight: .semibold).monospaced())
                    .tracking(1.0)
                    .foregroundStyle(textFaintColor)
                    .padding(.top, 8)
            }

            // Settings access — iPad doesn't have a nav bar gear icon
            // like HistoryView on iPhone, so we surface it in the sidebar.
            // macOS also shows it here (tray delegates to the main window).
            Section {
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(textDimColor)
                            .frame(width: 20, alignment: .center)
                        Text("Settings")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(textColor)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .background(surfaceColor)
        #endif
        .sheet(isPresented: $showSettings) {
            SettingsView()
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 640)
                #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dev.kindrazki.fastshared.openSettings"))) { _ in
            showSettings = true
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: LibrarySelection) -> some View {
        let isActive = selection == item
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? activeSidebarColor : textDimColor)
                .frame(width: 20, alignment: .center)
            Text(item.label)
                #if os(macOS)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                #else
                .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                #endif
                .foregroundStyle(isActive ? activeSidebarColor : textColor)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var activeSidebarColor: Color {
        #if os(macOS)
        textColor
        #else
        BrandPalette.accent.hot
        #endif
    }

    /// Devices to render: hide ones not seen in the last 30 days, keep the
    /// local device first, then most-recently-seen.
    private var visibleDevices: [DeviceEntity] {
        let cutoff = Date().addingTimeInterval(-deviceVisibilityWindow)
        let local = localDeviceId
        return devices
            .filter { $0.lastSeenAt >= cutoff }
            .sorted { lhs, rhs in
                if (lhs.deviceId == local) != (rhs.deviceId == local) {
                    return lhs.deviceId == local
                }
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
    }

    /// This install's CloudKit sync device id — same key the engine publishes
    /// under. Read-only (never creates) so the sidebar just reflects state.
    private var localDeviceId: UUID? {
        let defaults = UserDefaults(suiteName: AppGroupConfig.identifier)
        guard let raw = defaults?.string(forKey: "cksync_device_id_v1") else { return nil }
        return UUID(uuidString: raw)
    }

    private var localPlatform: String {
        #if os(macOS)
        "mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }

    private func symbol(forPlatform platform: String) -> String {
        switch platform {
        case "ipad": return "ipad"
        case "mac": return "laptopcomputer"
        case "iphone": return "iphone"
        default: return "laptopcomputer.and.iphone"
        }
    }

    @ViewBuilder
    private func deviceRow(name: String, platform: String, isLocal: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(forPlatform: platform))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(textDimColor)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
            if isLocal {
                Text("This device")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(textFaintColor)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Real device name from the system (Mac hostname / iOS device name).
    private var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }
}

// MARK: - LibraryDetail

private struct LibraryDetail: View {
    let title: String
    let subtitle: String
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
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                if rows.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .padding(.bottom, 48)
                } else {
                    tableHeader
                        .padding(.horizontal, 32)
                    Divider().overlay(lineColor)
                    tableRows
                        .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(groundColor)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search shares")
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let label = nextExpiryLabel {
                Text(label)
                    .font(.system(size: 12, weight: .bold).monospaced())
                    .tracking(1.2)
                    .foregroundStyle(BrandPalette.accentHot)
            }

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        #if os(macOS)
                        // HIG macOS largeTitle = 26pt bold; push to 34 for hero weight.
                        .font(.system(size: 34, weight: .bold))
                        #else
                        .font(.system(size: 40, weight: .bold))
                        #endif
                        .tracking(-0.5)
                        .foregroundStyle(textColor)
                    Text(subtitle)
                        #if os(macOS)
                        .font(.system(size: 14))
                        #else
                        .font(.system(size: 17))
                        #endif
                        .foregroundStyle(textDimColor)
                }

                Spacer(minLength: 16)

                dropButton
            }
        }
    }

    @ViewBuilder
    private var dropButton: some View {
        Button(action: onDropFile) {
            Label("Drop file", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        #if os(macOS)
        .keyboardShortcut("u", modifiers: [.command, .shift])
        #endif
        .help("Drop or pick a file (⌘⇧U)")
        .accessibilityLabel("Drop file")
    }

    // MARK: - Table header

    @ViewBuilder
    private var tableHeader: some View {
        HStack(spacing: 0) {
            headerCell("FILE")
                .frame(maxWidth: .infinity, alignment: .leading)
            headerCell("SIZE")
                .frame(width: 90, alignment: .leading)
            headerCell("LINK")
                .frame(width: 170, alignment: .leading)
            headerCell("EXPIRES")
                .frame(width: 120, alignment: .leading)
            Color.clear.frame(width: 40)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func headerCell(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .bold).monospaced())
            .tracking(1.2)
            .foregroundStyle(textFaintColor)
    }

    // MARK: - Table rows

    @ViewBuilder
    private var tableRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.token) { index, link in
                LibraryRow(
                    link: link,
                    now: now,
                    textColor: textColor,
                    textDimColor: textDimColor,
                    textFaintColor: textFaintColor,
                    lineColor: lineColor,
                    onCopy: { onCopy(link) },
                    onRevoke: { onRevoke(link) },
                    onShare: { onShare(link) }
                )
                .padding(.horizontal, 32)
                if index < rows.count - 1 {
                    Divider()
                        .overlay(lineColor.opacity(0.6))
                        .padding(.leading, 32)
                }
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            // Friendly icon tile — no tiny mystery arc.
            ZStack {
                Circle()
                    .fill(BrandPalette.accent.hot.opacity(0.10))
                    .frame(width: 96, height: 96)
                Image(systemName: "paperplane")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(BrandPalette.accent.hot)
                    .offset(x: -2, y: 1)
            }
            .padding(.top, 12)

            VStack(spacing: 8) {
                Text("No shares yet")
                    #if os(macOS)
                    .font(.system(size: 22, weight: .semibold))
                    #else
                    .font(.system(size: 24, weight: .semibold))
                    #endif
                    .foregroundStyle(textColor)
                Text("Drop a file into this window, or press ⌘⇧U to pick one.")
                    #if os(macOS)
                    .font(.system(size: 14))
                    #else
                    .font(.system(size: 16))
                    #endif
                    .foregroundStyle(textDimColor)
                    .multilineTextAlignment(.center)
            }

            Button(action: onDropFile) {
                Label("Pick a file", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 48)
    }
}

// MARK: - LibraryRow

private struct LibraryRow: View {
    let link: ShareLinkEntity
    let now: Date
    let textColor: Color
    let textDimColor: Color
    let textFaintColor: Color
    let lineColor: Color

    let onCopy: () -> Void
    let onRevoke: () -> Void
    let onShare: () -> Void

    @State private var copyFlash = false
    @State private var isHovering = false

    private var hoverBackground: Color {
        #if os(macOS)
        Color(nsColor: .selectedControlColor).opacity(0.18)
        #else
        Color.primary.opacity(0.04)
        #endif
    }

    private var remaining: TimeInterval { max(0, link.expiresAt.timeIntervalSince(now)) }
    private var retention: TimeInterval { max(0, link.expiresAt.timeIntervalSince(link.createdAt)) }
    private var progress: Double { retention > 0 ? max(0, min(1, remaining / retention)) : 0 }
    private var tier: ExpiryTier { ExpiryTier.tier(for: remaining) }

    var body: some View {
        HStack(spacing: 0) {
            // FILE column — urgency strip + glyph + filename stack.
            HStack(spacing: 12) {
                Capsule()
                    .fill(tier.urgencyColor)
                    .frame(width: 3, height: 28)

                leadingGlyph
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        #if os(macOS)
                        .font(.system(size: 14, weight: .semibold))
                        #else
                        .font(.system(size: 16, weight: .semibold))
                        #endif
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(RelativeDateTimeFormatter.cached.localizedString(for: link.createdAt, relativeTo: now))
                        .font(.system(size: 11))
                        .foregroundStyle(textFaintColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // SIZE
            Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                .font(.system(size: 13, design: .monospaced).monospacedDigit())
                .foregroundStyle(textDimColor)
                .frame(width: 90, alignment: .leading)

            // LINK — tap to copy.
            Button {
                onCopy()
                withAnimation(.easeOut(duration: 0.1)) { copyFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.3)) { copyFlash = false }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(shortPath)
                        .font(.system(size: 13, design: .monospaced))
                    Image(systemName: copyFlash ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(isHovering || copyFlash ? 1 : 0)
                }
                .foregroundStyle(copyFlash ? BrandPalette.accent.hot.opacity(0.6) : BrandPalette.accent.hot)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 160, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy link")
            .frame(width: 170, alignment: .leading)

            // EXPIRES — ring + countdown.
            HStack(spacing: 8) {
                UrgencyRing(progress: progress, size: 18, stroke: 2.5)
                Text(ExpiryFormatter.remaining(remaining))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(tier.urgencyColor)
            }
            .frame(width: 120, alignment: .leading)

            // Options menu.
            Menu {
                Button { onCopy() } label: { Label("Copy link", systemImage: "doc.on.doc") }
                Button { onShare() } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                Divider()
                Button(role: .destructive) { onRevoke() } label: {
                    Label("Revoke", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textDimColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 40)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? hoverBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BrandPalette.accentHot.opacity(0.14))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandPalette.accentHot)
            }
        } else {
            FileGlyph(contentType: link.contentType, size: 30)
        }
    }

    private var filename: String {
        if link.isBundle {
            let n = max(link.bundledAssets.count, 1)
            return n == 1 ? "1 file" : "\(n) files"
        }
        return link.originalFilename ?? link.token
    }

    /// Renders `/s/{token}` even if the server ships a longer URL. Stable width,
    /// matches the prototype.
    private var shortPath: String {
        "/s/\(link.token)"
    }
}

// MARK: - Relative formatter cache

private extension RelativeDateTimeFormatter {
    static let cached: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - Drop overlay

private struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(BrandPalette.accent.hot)
                Text("Drop to share")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BrandPalette.accent.hot)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(BrandPalette.accent.hot, style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
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
