import SwiftUI
import SwiftData
import FastSharedCore
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

/// The Hub. A live ledger of every link still in the wild.
///
/// Composition (top → bottom):
///  - hero metric (active count + nearest expiry + urgency spark bar)
///  - search / filter strip
///  - grouped list, bucketed by urgency
///  - floating "+" FAB on iOS
///
/// The whole page is driven by a single `TimelineView` tick (once per second) so countdowns stay live
/// and rows reshuffle between urgency sections as they decay. That's intentional — the Hub is the
/// product's answer to *"what's still out there?"* and that answer is always changing.
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
                .ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let now = timeline.date
                let snapshot = ExpirySnapshot.build(from: filtered(links), now: now)
                content(now: now, snapshot: snapshot)
            }

            #if os(iOS)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    floatingAddButton
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 28)
            #endif
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.milk)
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .searchable(text: $searchText,
                    placement: .automatic,
                    prompt: Text("search by name or token").foregroundStyle(BrandPalette.milk.opacity(0.5)))
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
                VStack(spacing: 0) {
                    HeroCountMetric(count: snapshot.activeCount,
                                    nearestRemaining: snapshot.nearestRemaining,
                                    referenceDate: now)

                    if snapshot.activeCount == 0 && !searchText.isEmpty {
                        searchEmpty
                    } else {
                        ledger(snapshot: snapshot, now: now)
                    }

                    Color.clear.frame(height: 120)
                }
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
                .foregroundStyle(BrandPalette.milk.opacity(0.5))
            Text("Nothing in the ledger matches ")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(BrandPalette.milk.opacity(0.8))
            + Text("\"\(searchText)\"")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(BrandPalette.amber)
            + Text(".")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(BrandPalette.milk.opacity(0.8))
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func ledger(snapshot: ExpirySnapshot, now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(snapshot.grouped.enumerated()), id: \.element.tier) { sectionIndex, group in
                VStack(spacing: 0) {
                    SectionHeaderStylized(title: group.tier.headline,
                                          accent: group.tier.accent,
                                          count: group.links.count)
                        .padding(.horizontal, 24)
                        .padding(.top, sectionIndex == 0 ? 28 : 20)

                    ForEach(Array(group.links.enumerated()), id: \.element.token) { rowIndex, link in
                        let absoluteIndex = min(11, sectionIndex * 8 + rowIndex)
                        NavigationLink(value: link.persistentModelID) {
                            LinkRow(link: link,
                                    now: now,
                                    onCopy: { copyLink(link) },
                                    onRevoke: { Task { await revoke(link) } })
                                .padding(.horizontal, 24)
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

                        if rowIndex < group.links.count - 1 {
                            Rectangle()
                                .fill(BrandPalette.milk.opacity(0.05))
                                .frame(height: 1)
                                .padding(.horizontal, 24)
                        }
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
                .foregroundStyle(BrandPalette.ink)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(BrandPalette.amber)
                        .shadow(color: BrandPalette.amber.opacity(0.5), radius: 20, y: 4)
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

/// When there is nothing in the wild. A confident void — no sad face, no empty box.
struct HubEmptyState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: geo.size.height * 0.12)

                amberSphere
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 18) {
                    Text("Nothing")
                        .font(.system(size: 72, weight: .bold))
                        .tracking(-3.2)
                    + Text("\nin the wild.")
                        .font(.system(size: 72, weight: .bold))
                        .tracking(-3.2)
                        .foregroundStyle(BrandPalette.amber)

                    Text("Share a file to FastShared and it'll land here. Every link is a countdown.")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(BrandPalette.milk.opacity(0.65))
                        .frame(maxWidth: 360, alignment: .leading)
                }
                .foregroundStyle(BrandPalette.milk)
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
                .foregroundStyle(BrandPalette.amber.opacity(0.75))
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

    private var amberSphere: some View {
        ZStack {
            Circle()
                .fill(BrandPalette.amber.opacity(0.18))
                .frame(width: 140, height: 140)
                .blur(radius: 36)
            Circle()
                .stroke(BrandPalette.amber.opacity(0.55), lineWidth: 1.2)
                .frame(width: 68, height: 68)
            Circle()
                .fill(RadialGradient(colors: [BrandPalette.ember, BrandPalette.amber],
                                     center: .center,
                                     startRadius: 0,
                                     endRadius: 20))
                .frame(width: 34, height: 34)
                .shadow(color: BrandPalette.amber.opacity(0.6), radius: 16)
        }
        .accessibilityHidden(true)
    }
}
