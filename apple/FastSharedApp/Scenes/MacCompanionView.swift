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

    // MARK: - Adaptive palette helpers

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
        Task {
            _ = try? await service.enqueueDrop(urls: urls)
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
            _ = try? await service.enqueueDrop(urls: urls)
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

#Preview("MacCompanionView") {
    MacCompanionView()
        .frame(width: 1100, height: 720)
        .preferredColorScheme(.dark)
}
#endif
