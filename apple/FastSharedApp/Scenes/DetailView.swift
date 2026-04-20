import SwiftUI
import SwiftData
import FastSharedCore

/// Link detail — redesigned pixel-perfect layout.
///
/// Composition (top → bottom):
///  - Custom nav bar (back + ellipsis)
///  - File header (icon tile + name/meta)
///  - Countdown hero card (urgency-tinted)
///  - Share link card (mono URL + Copy button)
///  - Stats grid (OPENED + LAST SEEN)
///  - Extend expiration row
///  - Floating action dock (Stop sharing)
struct DetailView: View {
    let linkID: PersistentIdentifier

    @Environment(\.modelContext) private var modelContext
    @Environment(\.clipboard) private var clipboard
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var link: ShareLinkEntity?
    @State private var showRevokeConfirm = false
    @State private var revoking: Bool = false
    @State private var errorMessage: String?
    @State private var copyTick: Int = 0
    @State private var revokeTick: Int = 0

    // MARK: - Theme helpers

    private var ground: Color {
        colorScheme == .dark
            ? BrandPalette.friendlyGroundDark
            : BrandPalette.friendlyGround
    }
    private var paper: Color {
        colorScheme == .dark
            ? BrandPalette.friendlyCanvasDark
            : .white
    }
    private var surface0: Color {
        colorScheme == .dark
            ? BrandPalette.friendlySurface0Dark
            : BrandPalette.friendlySurface0
    }
    private var textPrimary: Color {
        colorScheme == .dark
            ? BrandPalette.friendlyTextDark
            : BrandPalette.friendlyText
    }
    private var textDim: Color {
        colorScheme == .dark
            ? BrandPalette.friendlyTextDimDark
            : BrandPalette.friendlyTextDim
    }
    private var textFaint: Color {
        colorScheme == .dark
            ? BrandPalette.friendlyTextFaintDark
            : BrandPalette.friendlyTextFaint
    }
    private var line: Color {
        colorScheme == .dark
            ? BrandPalette.friendlyLineDark
            : BrandPalette.friendlyLine
    }
    private var lineStrong: Color {
        colorScheme == .dark
            ? BrandPalette.friendlyLineStrongDark
            : BrandPalette.friendlyLineStrong
    }

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()

            Group {
                if let link {
                    content(for: link)
                } else {
                    ProgressView()
                        .tint(BrandPalette.accentHot)
                }
            }
        }
        .foregroundStyle(textPrimary)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarHidden(true)
        .sensoryFeedback(.success, trigger: copyTick)
        .sensoryFeedback(.impact(weight: .heavy), trigger: revokeTick)
        #endif
        .task(id: linkID) { await load() }
    }

    @ViewBuilder
    private func content(for link: ShareLinkEntity) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let remaining = max(0, link.expiresAt.timeIntervalSince(now))
            let retention = max(0, link.expiresAt.timeIntervalSince(link.createdAt))
            let progress = retention > 0 ? max(0, min(1, remaining / retention)) : 0

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        navBar

                        fileHeader(link: link, now: now)
                            .padding(.top, 20)
                            .padding(.horizontal, 20)

                        countdownHeroCard(link: link, remaining: remaining)
                            .padding(.top, 24)
                            .padding(.horizontal, 20)

                        linkCard(link: link)
                            .padding(.top, 14)
                            .padding(.horizontal, 20)

                        statsGrid(link: link, now: now)
                            .padding(.top, 14)
                            .padding(.horizontal, 20)

                        extendRow
                            .padding(.top, 10)
                            .padding(.horizontal, 20)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(BrandPalette.urgencyCritical)
                                .padding(.top, 10)
                                .padding(.horizontal, 20)
                        }

                        Color.clear.frame(height: 130)
                    }
                }
                .scrollIndicators(.hidden)

                actionDock(link: link)
            }
        }
        .confirmationDialog("Revoke this link?",
                            isPresented: $showRevokeConfirm,
                            titleVisibility: .visible) {
            Button("Revoke link", role: .destructive) {
                revokeTick &+= 1
                Task { await revoke(link) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone with the link will lose access immediately. The media is still deleted on the scheduled date.")
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Shares")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(BrandPalette.accentHot)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                // placeholder for overflow menu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - File header

    private func fileHeader(link: ShareLinkEntity, now: Date) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon tile
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(surface0)
                    .frame(width: 56, height: 56)
                Image(systemName: fileIcon(for: link.contentType))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(BrandPalette.accentHot)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(link.originalFilename ?? link.token)
                    .font(.system(size: 17, weight: .bold))
                    .kerning(-0.017 * 17)
                    .foregroundStyle(textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
                    Text("·")
                    Text("Shared \(ExpiryFormatter.createdAgo(link.createdAt, now: now))")
                }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(textDim)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Countdown hero card

    private func countdownHeroCard(link: ShareLinkEntity, remaining: TimeInterval) -> some View {
        let tier = ExpiryTier.tier(for: remaining)
        let urgencyColor = tier.urgencyColor
        let bgColor = colorScheme == .dark ? tier.urgencyBgDark : tier.urgencyBgLight

        return VStack(spacing: 0) {
            // Tier label
            Text(heroTierLabel(tier: tier, link: link))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(urgencyColor)

            // Big number + unit
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(heroNumber(remaining: remaining, link: link))
                    .font(.system(size: 64, weight: .bold).monospacedDigit())
                    .kerning(-0.04 * 64)
                    .foregroundStyle(textPrimary)

                Text(heroUnit(remaining: remaining, link: link))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(textPrimary)
            }
            .padding(.top, 6)

            // Exact time footnote
            Text(heroFootnote(link: link))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(textDim)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(urgencyColor.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Link card

    private func linkCard(link: ShareLinkEntity) -> some View {
        let urlString = link.shortURL.absoluteString
        return VStack(alignment: .leading, spacing: 8) {
            Text("SHARE LINK")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(textDim)

            HStack(alignment: .center, spacing: 10) {
                Text(urlString)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    clipboard.copy(urlString)
                    copyTick &+= 1
                } label: {
                    Text("Copy")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(BrandPalette.accentHot, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(line, lineWidth: 1)
                )
        )
    }

    // MARK: - Stats grid

    private func statsGrid(link: ShareLinkEntity, now: Date) -> some View {
        HStack(spacing: 10) {
            statTile(label: "OPENED", value: "\(link.accessCount)")
            statTile(
                label: "LAST SEEN",
                value: link.lastAccessedAt.map { ExpiryFormatter.createdAgo($0, now: now) } ?? "—"
            )
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .tracking(0.55)
                .foregroundStyle(textDim)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .kerning(-0.02 * 20)
                .foregroundStyle(textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(line, lineWidth: 1)
                )
        )
    }

    // MARK: - Extend row

    private var extendRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Extend expiration")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textPrimary)
                Text("Add 24 h · 3 d · 7 d")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(textDim)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(textFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(line, lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Action dock

    private func actionDock(link: ShareLinkEntity) -> some View {
        let isActive = link.status == .active && link.expiresAt > .now
        return VStack(spacing: 0) {
            // gradient fade from transparent to ground
            LinearGradient(
                stops: [
                    .init(color: ground.opacity(0), location: 0),
                    .init(color: ground.opacity(1), location: 0.7),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .allowsHitTesting(false)

            VStack(spacing: 10) {
                // Stop sharing
                Button {
                    showRevokeConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Stop sharing now")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(BrandPalette.urgencyCritical)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BrandPalette.urgencyCritical.opacity(0.31), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isActive || revoking)
                .opacity(isActive && !revoking ? 1 : 0.4)

                // Share + Open row
                HStack(spacing: 10) {
                    #if os(iOS)
                    ShareLink(item: link.shortURL) {
                        dockSecondaryLabel(title: "Share")
                    }
                    .disabled(!isActive)
                    .opacity(isActive ? 1 : 0.4)
                    #else
                    Button {} label: { dockSecondaryLabel(title: "Share") }
                        .buttonStyle(.plain)
                        .disabled(!isActive)
                    #endif

                    Link(destination: link.shortURL) {
                        dockSecondaryLabel(title: "Open in browser")
                    }
                    .disabled(!isActive)
                    .opacity(isActive ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .background(ground)
        }
    }

    private func dockSecondaryLabel(title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(textDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(line, lineWidth: 1)
                    )
            )
    }

    // MARK: - Hero helpers

    private func heroTierLabel(tier: ExpiryTier, link: ShareLinkEntity) -> String {
        guard link.status == .active && link.expiresAt > .now else {
            return link.status == .revoked ? "REVOKED" : "EXPIRED"
        }
        switch tier {
        case .underOneMinute: return "EXPIRES NOW"
        case .underOneHour:   return "EXPIRES SOON"
        case .underSixHours:  return "EXPIRES TODAY"
        case .underOneDay:    return "EXPIRES TODAY"
        case .later:          return "ACTIVE"
        case .forever:        return "ACTIVE"
        }
    }

    private func heroNumber(remaining: TimeInterval, link: ShareLinkEntity) -> String {
        guard link.status == .active && link.expiresAt > .now else { return "0" }
        let s = Int(max(0, remaining))
        if s < 3600 { return "\(s / 60)" }
        if s < 86_400 { return "\(s / 3600)" }
        return "\(s / 86_400)"
    }

    private func heroUnit(remaining: TimeInterval, link: ShareLinkEntity) -> String {
        guard link.status == .active && link.expiresAt > .now else { return "min" }
        let s = Int(max(0, remaining))
        if s < 3600 { return "min" }
        if s < 86_400 { return "h" }
        let d = s / 86_400
        return d == 1 ? "day" : "days"
    }

    private func heroFootnote(link: ShareLinkEntity) -> String {
        let formatted = link.expiresAt.formatted(.dateTime.hour().minute())
        let isToday = Calendar.current.isDateInToday(link.expiresAt)
        let isTomorrow = Calendar.current.isDateInTomorrow(link.expiresAt)
        if isToday {
            return "at \(formatted) today"
        } else if isTomorrow {
            return "at \(formatted) tomorrow"
        } else {
            return "at \(link.expiresAt.formatted(.dateTime.month().day().hour().minute()))"
        }
    }

    // MARK: - File icon helper

    private func fileIcon(for contentType: String) -> String {
        let ct = contentType.lowercased()
        if ct.hasPrefix("image/")   { return "photo" }
        if ct.hasPrefix("video/")   { return "film" }
        if ct.hasPrefix("audio/")   { return "waveform" }
        if ct.contains("pdf")       { return "doc.richtext" }
        if ct.contains("zip") || ct.contains("gzip") || ct.contains("archive") {
            return "archivebox"
        }
        if ct.hasPrefix("text/")    { return "doc.text" }
        return "doc"
    }

    // MARK: - Actions

    private func load() async {
        let descriptor = FetchDescriptor<ShareLinkEntity>()
        if let results = try? modelContext.fetch(descriptor) {
            link = results.first(where: { $0.persistentModelID == linkID })
        }
    }

    private func revoke(_ link: ShareLinkEntity) async {
        guard let orchestrator else {
            errorMessage = "Revoke is unavailable in this build."
            return
        }
        revoking = true
        defer { revoking = false }
        do {
            try await orchestrator.revoke(token: link.token)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
