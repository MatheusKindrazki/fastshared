import SwiftUI
import SwiftData
import FastSharedCore
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Query(sort: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)]) private var links: [ShareLinkEntity]

    @State private var viewModel: HistoryViewModel?
    @State private var searchText: String = ""
    @State private var showImporter: Bool = false

    private var filtered: [ShareLinkEntity] {
        guard !searchText.isEmpty else { return links }
        let needle = searchText.lowercased()
        return links.filter { link in
            (link.originalFilename ?? "").lowercased().contains(needle) ||
            link.token.lowercased().contains(needle)
        }
    }

    var body: some View {
        Group {
            if links.isEmpty {
                EmptyStateView()
            } else {
                list
            }
        }
        .navigationTitle("FastShared")
        .searchable(text: $searchText, prompt: "Search")
        #if os(iOS)
        .refreshable {
            await viewModel?.refresh()
        }
        .overlay(alignment: .bottomTrailing) {
            floatingAddButton
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        #endif
        .task {
            if viewModel == nil {
                viewModel = HistoryViewModel(apiClient: apiClient, orchestrator: orchestrator)
            }
            await viewModel?.refresh(visibleLinks: links)
        }
    }

    private var list: some View {
        List(filtered) { link in
            NavigationLink(value: link.persistentModelID) {
                HistoryRowView(link: link)
            }
        }
        .navigationDestination(for: PersistentIdentifier.self) { id in
            DetailView(linkID: id)
        }
    }

    #if os(iOS)
    private var floatingAddButton: some View {
        Button {
            showImporter = true
        } label: {
            Image(systemName: "plus")
                .font(.title.weight(.semibold))
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
                .shadow(radius: 6, y: 3)
        }
        .padding(20)
        .accessibilityLabel("Upload file")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let service = uploadService else { return }
        Task {
            _ = try? await service.enqueueDrop(urls: urls)
        }
    }
    #endif
}

struct HistoryRowView: View {
    let link: ShareLinkEntity

    var body: some View {
        // WHY: TimelineView drives a cheap 30s repaint so countdown badges stay live without manual reloads.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: 12) {
                Image(systemName: iconName(for: link.contentType))
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.originalFilename ?? link.token)
                        .font(.body)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                        Text("·")
                        Text(link.retention.displayName)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                CountdownBadge(link: link, now: timeline.date)
            }
            .padding(.vertical, 4)
        }
    }

    private func iconName(for contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType.hasPrefix("video/") { return "film" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        if contentType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}

struct CountdownBadge: View {
    let link: ShareLinkEntity
    let now: Date

    var body: some View {
        let state = CountdownBadge.state(for: link, now: now)
        Text(state.text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(state.background, in: Capsule())
            .foregroundStyle(state.foreground)
    }

    struct Style {
        let text: String
        let background: Color
        let foreground: Color
    }

    static func state(for link: ShareLinkEntity, now: Date) -> Style {
        let inactive = link.linkStatus != LinkStatus.active.rawValue
        // WHY: "Removed" means the media itself is gone; we infer that today from delete_after + non-active status
        // until the server surfaces a dedicated deleted_at per asset.
        if inactive && link.deleteAfter <= now {
            return Style(text: "Removed", background: Color.secondary.opacity(0.2), foreground: .secondary)
        }
        if inactive || link.expiresAt <= now {
            return Style(text: "Expired", background: Color.secondary.opacity(0.2), foreground: .secondary)
        }
        let remaining = link.expiresAt.timeIntervalSince(now)
        if remaining <= 30 * 60 {
            return Style(text: formatRemaining(remaining),
                         background: Color.red.opacity(0.18),
                         foreground: .red)
        }
        if remaining <= 6 * 60 * 60 {
            return Style(text: formatRemaining(remaining),
                         background: Color.orange.opacity(0.18),
                         foreground: .orange)
        }
        return Style(text: formatRemaining(remaining),
                     background: Color.green.opacity(0.18),
                     foreground: .green)
    }

    static func formatRemaining(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s >= 86_400 {
            let days = s / 86_400
            return "\(days)d"
        }
        if s >= 3_600 {
            let hours = s / 3_600
            return "\(hours)h"
        }
        if s >= 60 {
            let mins = s / 60
            return "\(mins)m"
        }
        return "<1m"
    }
}
