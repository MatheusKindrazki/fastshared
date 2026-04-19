import SwiftUI
import SwiftData
import FastSharedCore
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

/// The Hub — `design/screens.jsx` → `Hub()`.
///
/// Composition (top → bottom):
///  - small brand chip (sphere + wordmark) + gear icon
///  - "next to expire" hero: Ring + filename + short URL
///  - summary strip: 3-up (ACTIVE / SENDING / DEFAULT)
///  - manifest section header + list of amber file cards
///  - FAB bottom-right for upload
///
/// Driven by a `TimelineView` tick (once per second) so countdowns stay live
/// and rows reshuffle between urgency sections as they decay.
struct HistoryView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.clipboard) private var clipboard
    @Environment(\.paywallCoordinator) private var paywallCoordinator
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
            BrandPalette.ground
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
                .padding(.bottom, 94)
        }
        #endif
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.text)
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        ScrollView {
            VStack(spacing: 0) {
                brandHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                if let next = snapshot.grouped.first?.links.first {
                    heroBlock(next: next, now: now)
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                } else if searchText.isEmpty {
                    emptyHero
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                }

                summaryStrip(snapshot: snapshot)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                manifestSection(snapshot: snapshot, now: now)
                    .padding(.top, 22)

                Color.clear.frame(height: 160)
            }
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    // MARK: - Brand header

    private var brandHeader: some View {
        HStack(spacing: 10) {
            // v3 Hub header — BrandLockup replaces the hand-rolled sphere+wordmark chip.
            BrandLockup(markSize: 26, textSize: 15)

            Spacer()

            Button {
                // navigation handled elsewhere — placeholder IconBtn
            } label: {
                iconTile("gearshape")
            }
            .buttonStyle(.plain)
        }
    }

    private func iconTile(_ systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(BrandPalette.paper)
            .frame(width: 36, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(BrandPalette.line, lineWidth: 1)
            )
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(BrandPalette.textDim)
            )
    }

    // MARK: - Hero (next-to-expire)

    private func heroBlock(next: ShareLinkEntity, now: Date) -> some View {
        let accent = BrandPalette.amberAccent
        let remaining = max(0, next.expiresAt.timeIntervalSince(now))
        let retention = max(0, next.expiresAt.timeIntervalSince(next.createdAt))
        let progress = retention > 0 ? max(0, min(1, remaining / retention)) : 0

        return VStack(alignment: .leading, spacing: 10) {
            Mono("next to expire", color: BrandPalette.textFaint)

            NavigationLink(value: next.persistentModelID) {
                HStack(alignment: .bottom, spacing: 14) {
                    Ring(progress: progress,
                         size: 78,
                         stroke: 5,
                         label: compactRemaining(remaining),
                         sub: "LEFT")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(next.originalFilename ?? next.token)
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(BrandPalette.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("fastsha.red/s/\(next.token)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(accent.hot)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.bottom, 2)

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Mono("ready when you are", color: BrandPalette.textFaint)
            Text("Share a file")
                .font(.system(size: 34, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(BrandPalette.text)
            Text("Your first temporary link will land here, already copied.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(BrandPalette.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary strip

    private func summaryStrip(snapshot: ExpirySnapshot) -> some View {
        let totalSending = totalBytesInFlight(snapshot: snapshot)
        let defaultRetention = RetentionPolicy.defaultFromAppGroup().displayName.uppercased()

        let cells: [(String, String)] = [
            (String(format: "%02d", snapshot.activeCount), "ACTIVE"),
            (totalSending, "SENDING"),
            (defaultRetention, "DEFAULT"),
        ]

        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, cell in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cell.0)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .tracking(-0.3)
                            .foregroundStyle(BrandPalette.text)
                        Mono(cell.1, size: 9, track: 1.2, color: BrandPalette.textFaint)
                    }
                    Spacer()
                }
                .padding(.leading, idx == 0 ? 0 : 12)
                .overlay(alignment: .leading) {
                    if idx > 0 {
                        Rectangle()
                            .fill(BrandPalette.line)
                            .frame(width: 1)
                            .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BrandPalette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BrandPalette.line, lineWidth: 1)
                )
        )
    }

    private func totalBytesInFlight(snapshot: ExpirySnapshot) -> String {
        let total = snapshot.grouped.flatMap(\.links).reduce(Int64(0)) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file).uppercased()
    }

    // MARK: - Manifest list

    @ViewBuilder
    private func manifestSection(snapshot: ExpirySnapshot, now: Date) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Mono("manifest · \(String(format: "%02d", snapshot.activeCount))",
                     color: BrandPalette.amberAccent.hot)
                Rectangle().fill(BrandPalette.line).frame(height: 1)
                Mono("sorted: urgency", size: 10, color: BrandPalette.textFaint)
            }
            .padding(.horizontal, 20)

            if snapshot.activeCount == 0 && !searchText.isEmpty {
                searchEmpty
            } else if snapshot.activeCount == 0 {
                Text("No active links.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(BrandPalette.textFaint)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.grouped.flatMap(\.links), id: \.token) { link in
                        NavigationLink(value: link.persistentModelID) {
                            HubLinkCard(link: link, now: now)
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
                            .tint(BrandPalette.amberAccent.fade)

                            Button {
                                copyLink(link)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .tint(BrandPalette.amberAccent.hot)
                        }
                        #endif
                    }
                }
            }
        }
    }

    private var searchEmpty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Mono("no match", color: BrandPalette.textFaint)
            Text("Nothing matches \"\(searchText)\".")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(BrandPalette.textDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func compactRemaining(_ s: TimeInterval) -> String {
        let seconds = Int(max(0, s))
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds/60)m" }
        if seconds < 86_400 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        let d = seconds / 86_400
        let h = (seconds % 86_400) / 3600
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }

    #if os(iOS)
    private var floatingAddButton: some View {
        let accent = BrandPalette.amberAccent
        return Button {
            showImporter = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.hot)
                        .shadow(color: accent.hot.opacity(0.33), radius: 18, y: 10)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: showImporter)
        .accessibilityLabel("Upload file")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let service = uploadService else { return }
        Task {
            do {
                _ = try await service.enqueueDrop(urls: urls)
            } catch let gate as SubscriptionGate {
                await MainActor.run { routePaywall(for: gate) }
            } catch let error as APIError {
                if case .paymentRequired(let code, _) = error {
                    await MainActor.run { paywallCoordinator.present(.serverForced(errorCode: code)) }
                }
            } catch {
                // Swallow — Live Activity / toast handles visibility elsewhere.
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

// MARK: - HubLinkCard

/// One row in the manifest — per `design/screens.jsx` → `LinkCard()`.
///
/// A 4pt tier-colored left rail, a 38pt FileGlyph, filename + meta, trailing
/// compact Ring + mono remaining time.
struct HubLinkCard: View {
    let link: ShareLinkEntity
    let now: Date

    var body: some View {
        let remaining = max(0, link.expiresAt.timeIntervalSince(now))
        let retention = max(0, link.expiresAt.timeIntervalSince(link.createdAt))
        let progress = retention > 0 ? max(0, min(1, remaining / retention)) : 0
        let tierColor = tier(for: remaining)

        HStack(spacing: 0) {
            // Left tier rail.
            Rectangle()
                .fill(tierColor.opacity(0.85))
                .frame(width: 4)

            HStack(spacing: 12) {
                FileGlyph(contentType: link.contentType)

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.originalFilename ?? link.token)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(BrandPalette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                        Text("·")
                        Text("s/\(link.token.prefix(8))")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(BrandPalette.textFaint)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Ring(progress: progress, size: 30, stroke: 2.5, tint: tierColor)
                    Text(compactRemaining(remaining))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(tierColor)
                }
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BrandPalette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BrandPalette.line, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tier(for remaining: TimeInterval) -> Color {
        let accent = BrandPalette.amberAccent
        if remaining <= 3600 { return accent.fade }
        if remaining <= 86_400 { return accent.hot }
        return accent.soft
    }

    private func compactRemaining(_ s: TimeInterval) -> String {
        let seconds = Int(max(0, s))
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds/60)m" }
        if seconds < 86_400 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        let d = seconds / 86_400
        let h = (seconds % 86_400) / 3600
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }
}

