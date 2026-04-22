#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import FastSharedCore
import UniformTypeIdentifiers

// MARK: - Sidebar selection

enum MacSidebarSelection: Hashable {
    case all, endingSoon, thisWeek, expired
}

// MARK: - MacCompanionView

/// macOS companion window — sidebar + main layout.
///
/// Sidebar (220pt): brand lockup, navigation filters, settings footer.
/// Main: toolbar with search / new-share CTA, drop zone hint, share table.
///
/// All data comes from `@Query` on `ShareLinkEntity` — same SwiftData container
/// as iOS. No model creation here; read-only plus orchestrator actions.
struct MacCompanionView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.clipboard) private var clipboard
    @Environment(\.subscriptionStore) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)])
    private var allLinks: [ShareLinkEntity]

    @State private var selection: MacSidebarSelection = .all
    @State private var searchText: String = ""
    @State private var isDragTargeted: Bool = false
    @State private var viewModel: HistoryViewModel?
    @State private var showFileImporter: Bool = false

    // M4: aggregated bundle upload card. Shown while a multi-file drop runs
    // and dismissed shortly after completion; single uploads keep the existing
    // history-row indicator (orchestrator drives the row's progress directly).
    @State private var bundleCard: MacBundleCard? = nil
    @State private var bundleObserverTask: Task<Void, Never>? = nil

    // MARK: - Adaptive palette helpers — HIG semantic (NSColor bridges).

    private var groundColor: Color { Color(nsColor: .windowBackgroundColor) }
    private var canvasColor: Color { Color(nsColor: .controlBackgroundColor) }
    private var surface0Color: Color { Color(nsColor: .underPageBackgroundColor) }
    private var textColor: Color { Color(nsColor: .labelColor) }
    private var textDimColor: Color { Color(nsColor: .secondaryLabelColor) }
    private var textFaintColor: Color { Color(nsColor: .tertiaryLabelColor) }
    private var lineColor: Color { Color(nsColor: .separatorColor) }

    // MARK: - Filtered link sets

    private var now: Date { Date() }

    private var activeLinks: [ShareLinkEntity] {
        allLinks.filter { $0.linkStatus == LinkStatus.active.rawValue && $0.expiresAt > now }
    }
    private var endingSoonLinks: [ShareLinkEntity] {
        activeLinks.filter {
            let r = $0.expiresAt.timeIntervalSince(now)
            let tier = ExpiryTier.tier(for: r)
            return tier <= ExpiryTier.underOneDay
        }
    }
    private var thisWeekLinks: [ShareLinkEntity] {
        activeLinks.filter {
            let r = $0.expiresAt.timeIntervalSince(now)
            let tier = ExpiryTier.tier(for: r)
            return tier > ExpiryTier.underOneDay
        }
    }
    private var expiredLinks: [ShareLinkEntity] {
        allLinks.filter { $0.linkStatus != LinkStatus.active.rawValue || $0.expiresAt <= now }
    }

    private var displayedLinks: [ShareLinkEntity] {
        let base: [ShareLinkEntity]
        switch selection {
        case .all:         base = activeLinks
        case .endingSoon:  base = endingSoonLinks
        case .thisWeek:    base = thisWeekLinks
        case .expired:     base = expiredLinks
        }
        guard !searchText.isEmpty else { return base }
        let needle = searchText.lowercased()
        return base.filter {
            ($0.originalFilename ?? "").lowercased().contains(needle) ||
            $0.token.lowercased().contains(needle) ||
            $0.shortURLString.lowercased().contains(needle)
        }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, maxWidth: 220)
            mainArea
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(groundColor)
        .overlay(alignment: .bottomTrailing) {
            if let card = bundleCard {
                MacBundleProgressCard(card: card,
                                      canvasColor: canvasColor,
                                      surface0Color: surface0Color,
                                      textColor: textColor,
                                      textDimColor: textDimColor,
                                      lineColor: lineColor,
                                      onCopyLink: { clipboard.copy(card.shortUrl.absoluteString) })
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: bundleCard?.isComplete)
        .task {
            if viewModel == nil {
                viewModel = HistoryViewModel(apiClient: apiClient, orchestrator: orchestrator)
            }
            await viewModel?.refresh(visibleLinks: allLinks)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Brand lockup header
            VStack(alignment: .leading, spacing: 0) {
                BrandLockup(markSize: 22, textSize: 15)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
            }

            Divider()
                .overlay(lineColor)

            // Nav list
            VStack(spacing: 2) {
                navItem(label: "All shares",   tag: .all,        count: activeLinks.count)
                navItem(label: "Ending soon",  tag: .endingSoon, count: endingSoonLinks.count)
                navItem(label: "This week",    tag: .thisWeek,   count: thisWeekLinks.count)
                navItem(label: "Expired",      tag: .expired,    count: expiredLinks.count)
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)

            Spacer()

            // Footer
            VStack(spacing: 0) {
                lineColor
                    .frame(height: 1)

                Button {
                    // Open settings — placeholder; future navigation
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                        Text("Settings")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(textDimColor)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
        .background(surface0Color)
    }

    @ViewBuilder
    private func navItem(label: String, tag: MacSidebarSelection, count: Int) -> some View {
        let isActive = selection == tag
        Button {
            selection = tag
        } label: {
            HStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? BrandPalette.accentHot : textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle((isActive ? BrandPalette.accentHot : textColor).opacity(0.6))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? BrandPalette.accentHot.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main area

    private var mainArea: some View {
        VStack(spacing: 0) {
            toolbarRow
            lineColor.frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    dropZoneHint
                        .padding(.horizontal, 22)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    shareTableHeader
                        .padding(.horizontal, 22)
                        .padding(.top, 6)

                    shareTableCard
                        .padding(.horizontal, 22)
                        .padding(.bottom, 20)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(groundColor)
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            // Title block
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionTitle)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.02 * 18)
                    .foregroundStyle(textColor)

                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(textDimColor)
            }

            Spacer()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(textFaintColor)
                TextField("Search shares", text: $searchText)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .textFieldStyle(.plain)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(width: 220)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(canvasColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(lineColor, lineWidth: 1)
                    )
            )

            // New share button
            Button {
                showFileImporter = true
            } label: {
                Text("+ New share")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(BrandPalette.accentHot)
                            .shadow(color: BrandPalette.accentHot.opacity(0.27), radius: 3, x: 0, y: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 22)
    }

    private var selectionTitle: String {
        switch selection {
        case .all:        return "All shares"
        case .endingSoon: return "Ending soon"
        case .thisWeek:   return "This week"
        case .expired:    return "Expired"
        }
    }

    private var subtitleText: String {
        let active = activeLinks.count
        let ending = endingSoonLinks.count
        if active == 0 { return "No active shares" }
        if ending > 0 {
            return "\(active) active · \(ending) ending soon"
        }
        return "\(active) active"
    }

    // MARK: - Drop zone hint

    private var dropZoneHint: some View {
        HStack(spacing: 12) {
            Text("📎")
                .font(.system(size: 22))

            VStack(alignment: .leading, spacing: 3) {
                Text("Drop any file here to share")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor)
                Text("Or press ⌘⇧S from anywhere")
                    .font(.system(size: 12))
                    .foregroundStyle(textDimColor)
            }

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BrandPalette.accentHot.opacity(isDragTargeted ? 0.13 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            BrandPalette.accentHot.opacity(isDragTargeted ? 0.55 : 0.31),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        .onDrop(of: [UTType.fileURL, UTType.item], isTargeted: $isDragTargeted) { providers in
            handleDropProviders(providers)
            return true
        }
    }

    // MARK: - Share table header

    private var shareTableHeader: some View {
        HStack(spacing: 0) {
            Text("FILE")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SIZE")
                .frame(width: 100, alignment: .leading)
            Text("LINK")
                .frame(width: 170, alignment: .leading)
            Text("EXPIRES")
                .frame(width: 120, alignment: .leading)
            Spacer()
                .frame(width: 30)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(textFaintColor)
        .tracking(0.08 * 11)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
    }

    // MARK: - Share table card

    private var shareTableCard: some View {
        Group {
            if displayedLinks.isEmpty {
                emptyTableState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedLinks.enumerated()), id: \.element.token) { index, link in
                        if index > 0 {
                            lineColor.frame(height: 1)
                        }
                        MacShareRow(
                            link: link,
                            now: now,
                            canvasColor: canvasColor,
                            surface0Color: surface0Color,
                            textColor: textColor,
                            textDimColor: textDimColor,
                            textFaintColor: textFaintColor,
                            lineColor: lineColor,
                            onCopyLink: { copyLink(link) },
                            onRevoke: { Task { await viewModel?.revoke(link) } },
                            onDelete: { Task { await viewModel?.revoke(link) } }
                        )
                    }
                }
                .background(canvasColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(lineColor, lineWidth: 1)
                )
            }
        }
    }

    private var emptyTableState: some View {
        VStack(spacing: 12) {
            PlaneArcMark(size: 48)
                .opacity(0.5)
            Text("No shares here yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(textDimColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(lineColor, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func copyLink(_ link: ShareLinkEntity) {
        clipboard.copy(link.shortURLString)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let service = uploadService else { return }
        Task { await runDrop(urls: urls, service: service) }
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
            await runDrop(urls: urls, service: service)
        }
    }

    /// M4: dispatches a drop and, when the result is `.bundle`, watches the
    /// aggregate progress stream so the floating card can render
    /// "Sending {N} files · X%". Single uploads return immediately — their UI
    /// lives in the history row.
    @MainActor
    private func runDrop(urls: [URL], service: UploadServiceProtocol) async {
        do {
            switch try await service.enqueueDrop(urls: urls) {
            case .single:
                // Single-file drop — history row tracks progress.
                return
            case .bundle(let bundle):
                let count = bundle.jobs.count
                let total = bundle.totalBytes
                bundleCard = MacBundleCard(fileCount: count,
                                           progress: 0,
                                           bytesUploaded: 0,
                                           totalBytes: total,
                                           shortUrl: bundle.bundleShortUrl,
                                           isComplete: false)
                bundleObserverTask?.cancel()
                bundleObserverTask = Task { @MainActor in
                    for await fraction in bundle.aggregateProgress {
                        let bytes = Int64(Double(total) * max(0, min(1, fraction)))
                        bundleCard = MacBundleCard(fileCount: count,
                                                   progress: fraction,
                                                   bytesUploaded: bytes,
                                                   totalBytes: total,
                                                   shortUrl: bundle.bundleShortUrl,
                                                   isComplete: fraction >= 1.0)
                    }
                    // Stream finished. Hold the success card briefly so the
                    // user sees confirmation + clipboard hint.
                    bundleCard = MacBundleCard(fileCount: count,
                                               progress: 1.0,
                                               bytesUploaded: total,
                                               totalBytes: total,
                                               shortUrl: bundle.bundleShortUrl,
                                               isComplete: true)
                    try? await Task.sleep(nanoseconds: 4_500_000_000)
                    bundleCard = nil
                }
            }
        } catch {
            // Errors surface via the orchestrator's per-job failure markers;
            // we don't have a dedicated bundle error toast in this iteration.
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - MacShareRow

private struct MacShareRow: View {
    let link: ShareLinkEntity
    let now: Date

    let canvasColor: Color
    let surface0Color: Color
    let textColor: Color
    let textDimColor: Color
    let textFaintColor: Color
    let lineColor: Color

    let onCopyLink: () -> Void
    let onRevoke: () -> Void
    let onDelete: () -> Void

    @State private var copyFlash: Bool = false

    private var remaining: TimeInterval { max(0, link.expiresAt.timeIntervalSince(now)) }
    private var retention: TimeInterval { max(0, link.expiresAt.timeIntervalSince(link.createdAt)) }
    private var progress: Double { retention > 0 ? max(0, min(1, remaining / retention)) : 0 }
    private var tier: ExpiryTier { ExpiryTier.tier(for: remaining) }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1 — File
            HStack(spacing: 10) {
                FileGlyph(contentType: link.contentType, size: 28)
                Text(link.originalFilename ?? link.token)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Col 2 — Size
            Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(textDimColor)
                .frame(width: 100, alignment: .leading)

            // Col 3 — Link (tap to copy)
            Button {
                onCopyLink()
                withAnimation(.easeOut(duration: 0.1)) { copyFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.3)) { copyFlash = false }
                }
            } label: {
                Text(link.shortURLString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(copyFlash ? BrandPalette.accentHot.opacity(0.6) : BrandPalette.accentHot)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 160, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Copy link")
            .frame(width: 170, alignment: .leading)

            // Col 4 — Expires
            HStack(spacing: 6) {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(
                        tier.urgencyColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(-90))
                    .background(
                        Circle()
                            .stroke(tier.urgencyColor.opacity(0.15), lineWidth: 2)
                            .frame(width: 16, height: 16)
                    )

                Text(ExpiryFormatter.remaining(remaining))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tier.urgencyColor)
            }
            .frame(width: 120, alignment: .leading)

            // Col 5 — More menu
            Menu {
                Button {
                    onCopyLink()
                } label: {
                    Label("Copy link", systemImage: "doc.on.doc")
                }
                Button {
                    if let url = URL(string: link.shortURLString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in browser", systemImage: "safari")
                }
                Divider()
                Button(role: .destructive) {
                    onRevoke()
                } label: {
                    Label("Revoke", systemImage: "xmark.circle")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(textFaintColor)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }
}

// MARK: - Bundle progress card (M4)

/// Snapshot of an in-flight bundle upload, pushed into the overlay each tick.
struct MacBundleCard: Equatable {
    let fileCount: Int
    let progress: Double
    let bytesUploaded: Int64
    let totalBytes: Int64
    let shortUrl: URL
    let isComplete: Bool
}

/// Floating bottom-right card that shows aggregate bundle progress while a
/// drop is uploading; flips to a "Bundle ready" state when complete.
private struct MacBundleProgressCard: View {
    let card: MacBundleCard
    let canvasColor: Color
    let surface0Color: Color
    let textColor: Color
    let textDimColor: Color
    let lineColor: Color
    let onCopyLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BrandPalette.accentHot.opacity(card.isComplete ? 0.0 : 0.18))
                        .frame(width: 38, height: 38)
                    if card.isComplete {
                        ZStack {
                            Circle()
                                .fill(BrandPalette.accentHot)
                                .frame(width: 38, height: 38)
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    } else {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BrandPalette.accentHot)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(textColor)
                    Text(subline)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(textDimColor)
                }

                Spacer(minLength: 0)

                if card.isComplete {
                    Button(action: onCopyLink) {
                        Text("Copy link")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if !card.isComplete {
                MacBundleProgressBar(progress: card.progress, lineColor: lineColor)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(canvasColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(lineColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private var headline: String {
        card.isComplete ? "\(card.fileCount) files shared" : "Sending \(card.fileCount) files"
    }

    private var subline: String {
        if card.isComplete {
            return card.shortUrl.absoluteString
        }
        let sent = ByteCountFormatter.string(fromByteCount: card.bytesUploaded, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: card.totalBytes, countStyle: .file)
        return "\(sent) / \(total) · \(Int((card.progress * 100).rounded()))%"
    }
}

private struct MacBundleProgressBar: View {
    let progress: Double
    let lineColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(lineColor)
                    .frame(height: 5)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(BrandPalette.accentHot)
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, progress)))),
                           height: 5)
            }
        }
        .frame(height: 5)
    }
}

#Preview("MacCompanionView") {
    MacCompanionView()
        .frame(width: 1100, height: 720)
        .preferredColorScheme(.dark)
}
#endif
