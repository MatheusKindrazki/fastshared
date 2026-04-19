import SwiftUI
import SwiftData
import FastSharedCore
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

/// The Hub. A live manifest of every temporary link still available.
///
/// Composition (top → bottom):
///  - frosted manifest header (active count + nearest expiry + transfer rail)
///  - calm status chips
///  - grouped list, bucketed by urgency
///  - floating upload control on iOS
///
/// The whole page is driven by a single `TimelineView` tick (once per second) so countdowns stay live
/// and rows reshuffle between urgency sections as they decay. That's intentional — the Hub is the
/// product's answer to *"what can still be opened?"* and that answer is always changing.
struct HistoryView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.clipboard) private var clipboard
    @Query(sort: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)]) private var links: [ShareLinkEntity]

    @State private var viewModel: HistoryViewModel?
    @State private var searchText: String = ""
    @State private var showImporter: Bool = false
    @State private var copyPulseToken: String?
    @State private var revokePulseToken: String?

    private func filtered(_ source: [ShareLinkEntity]) -> [ShareLinkEntity] {
        guard !searchText.isEmpty else { return source }
        let needle = searchText.lowercased()
        return source.filter { link in
            (link.originalFilename ?? "").lowercased().contains(needle) ||
            link.token.lowercased().contains(needle)
        }
    }

    var body: some View {
        ZStack {
            BrandPalette.canvas
                .ignoresSafeArea(.all)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let now = timeline.date
                let snapshot = ExpirySnapshot.build(from: filtered(links), now: now)
                content(now: now, snapshot: snapshot)
            }
        }
        #if os(iOS)
        .overlay(alignment: .bottomTrailing) {
            floatingAddButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        #endif
        .preferredColorScheme(.light)
        .foregroundStyle(BrandPalette.ink)
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
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
        #if os(iOS)
        .navigationDestination(for: PersistentIdentifier.self) { id in
            DetailView(linkID: id)
        }
        #endif
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date, snapshot: ExpirySnapshot) -> some View {
        if snapshot.activeCount == 0 && searchText.isEmpty {
            HubEmptyState()
                .transition(.opacity.combined(with: .offset(y: 12)))
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    HeroCountMetric(count: snapshot.activeCount,
                                    nearestRemaining: snapshot.nearestRemaining,
                                    referenceDate: now)
                    ManifestSearchField(text: $searchText)
                        .padding(.horizontal, 20)

                    HubAssuranceStrip()
                        .padding(.horizontal, 20)

                    if snapshot.activeCount == 0 && !searchText.isEmpty {
                        searchEmpty
                    } else {
                        ledger(snapshot: snapshot, now: now)
                    }

                    Color.clear.frame(height: 112)
                }
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
    }

    private var searchEmpty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO MATCH")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(BrandPalette.dust)
            Text("Nothing in the manifest matches ")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(BrandPalette.ink.opacity(0.78))
            + Text("\"\(searchText)\"")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(BrandPalette.amber)
            + Text(".")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(BrandPalette.ink.opacity(0.78))
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct HubAssuranceStrip: View {
        private var items: [(String, String)] {
            [
                ("doc.on.doc", "Paste-ready"),
                ("lock.shield", "Signed reads"),
                ("timer", "Auto-delete")
            ]
        }

        var body: some View {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    Label(item.1, systemImage: item.0)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandPalette.ink.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(BrandPalette.line.opacity(0.75), lineWidth: 1)
                        )
                }
            }
        }
    }

    private struct ManifestSearchField: View {
        @Binding var text: String

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrandPalette.dust)
                TextField("file name or token", text: $text)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BrandPalette.ink)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandPalette.dust.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BrandPalette.line.opacity(0.8), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func ledger(snapshot: ExpirySnapshot, now: Date) -> some View {
        VStack(spacing: 18) {
            ForEach(Array(snapshot.grouped.enumerated()), id: \.element.tier) { sectionIndex, group in
                VStack(spacing: 8) {
                    SectionHeaderStylized(title: group.tier.headline,
                                          accent: group.tier.accent,
                                          count: group.links.count)
                        .padding(.horizontal, 20)
                        .padding(.top, sectionIndex == 0 ? 4 : 2)

                    ForEach(Array(group.links.enumerated()), id: \.element.token) { rowIndex, link in
                        let absoluteIndex = min(11, sectionIndex * 8 + rowIndex)
                        NavigationLink(value: link.persistentModelID) {
                            LinkRow(link: link,
                                    now: now,
                                    onCopy: { copyLink(link) },
                                    onRevoke: { Task { await revoke(link) } })
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
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
                        #if os(iOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task { await revoke(link) }
                            } label: {
                                Label("Revoke", systemImage: "xmark.circle")
                            }
                            .tint(BrandPalette.coral)

                            Button {
                                copyLink(link)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .tint(BrandPalette.amber)
                        }
                        #endif
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        ))
                        .animation(BrandMotion.transition.delay(Double(absoluteIndex) * 0.06),
                                   value: snapshot.activeCount)

                    }
                }
            }
        }
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
    private var floatingAddButton: some View {
        Button {
            showImporter = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(BrandPalette.lightText)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(BrandPalette.amber)
                        .shadow(color: BrandPalette.amber.opacity(0.28), radius: 18, y: 8)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: showImporter)
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

// MARK: - Empty state (inline)

/// When there are no active links. A calm workbench, ready for the next share.
struct HubEmptyState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: geo.size.height * 0.12)

                manifestStack
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 18) {
                    Text("Ready")
                        .font(.system(size: 56, weight: .bold))
                        .tracking(-2.0)
                    + Text("\nwhen you are.")
                        .font(.system(size: 56, weight: .bold))
                        .tracking(-2.0)
                        .foregroundStyle(BrandPalette.amber)

                    Text("Send a file to FastShared and the temporary link lands here, already copied.")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(BrandPalette.ink.opacity(0.62))
                        .frame(maxWidth: 360, alignment: .leading)
                }
                .foregroundStyle(BrandPalette.ink)
                .padding(.horizontal, 24)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                    Text("TRY THE SHARE SHEET FROM PHOTOS")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(BrandPalette.amber.opacity(0.8))
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(BrandMotion.transition) { appeared = true }
            }
        }
    }

    private var manifestStack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
                .frame(width: 148, height: 112)
                .rotationEffect(.degrees(-4))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BrandPalette.line.opacity(0.85), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BrandPalette.paper)
                .frame(width: 148, height: 112)
                .shadow(color: BrandPalette.ink.opacity(0.08), radius: 18, y: 10)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 7) {
                            Image(systemName: "link")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(BrandPalette.amber)
                            Text("fastsha.red")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(BrandPalette.ink)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(BrandPalette.line).frame(width: 92, height: 5)
                            Capsule().fill(BrandPalette.line.opacity(0.7)).frame(width: 68, height: 5)
                        }
                        UrgencySparkBar(remaining: 18 * 3600)
                    }
                    .padding(16)
                }
        }
        .accessibilityHidden(true)
    }
}
