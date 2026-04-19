import SwiftUI
import SwiftData
import FastSharedCore

struct DetailView: View {
    let linkID: PersistentIdentifier

    @Environment(\.modelContext) private var modelContext
    @Environment(\.clipboard) private var clipboard
    @Environment(\.uploadOrchestrator) private var orchestrator
    @Environment(\.dismiss) private var dismiss

    @State private var link: ShareLinkEntity?
    @State private var showRevokeConfirm = false
    @State private var revoking: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let link {
                content(for: link)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(link?.originalFilename ?? "Link")
        .task(id: linkID) { await load() }
    }

    @ViewBuilder
    private func content(for link: ShareLinkEntity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                thumbnail(for: link)
                infoGrid(for: link)
                actions(for: link)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .confirmationDialog("Revoke this link?",
                            isPresented: $showRevokeConfirm,
                            titleVisibility: .visible) {
            Button("Revoke link", role: .destructive) {
                Task { await revoke(link) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone with the link will lose access immediately. The media is still deleted on the scheduled date.")
        }
    }

    private func thumbnail(for link: ShareLinkEntity) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .aspectRatio(16.0/10.0, contentMode: .fit)
            .overlay {
                Image(systemName: iconName(for: link.contentType))
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
    }

    private func infoGrid(for link: ShareLinkEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Filename", link.originalFilename ?? "-")
            row("Type", link.contentType)
            row("Size", ByteCountFormatter.string(fromByteCount: link.sizeBytes, countStyle: .file))
            row("Created", link.createdAt.formatted(date: .abbreviated, time: .shortened))
            row("Retention", link.retention.displayName)
            row("Status", statusLabel(for: link))
            row("Expires", datePair(link.expiresAt))
            row("Media deleted", datePair(link.deleteAfter))
            row("Short URL", link.shortURL.absoluteString)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func datePair(_ date: Date) -> String {
        let absolute = date.formatted(date: .abbreviated, time: .shortened)
        let relative = date.formatted(.relative(presentation: .numeric))
        return "\(absolute) (\(relative))"
    }

    private func statusLabel(for link: ShareLinkEntity) -> String {
        switch link.status {
        case .active: return "Active"
        case .expired: return "Expired"
        case .revoked: return "Revoked"
        }
    }

    @ViewBuilder
    private func actions(for link: ShareLinkEntity) -> some View {
        let isActive = link.status == .active && link.expiresAt > Date()
        HStack(spacing: 12) {
            Button {
                clipboard.copy(link.shortURL.absoluteString)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isActive)

            ShareLink(item: link.shortURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(!isActive)

            Link(destination: link.shortURL) {
                Label("Open", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .disabled(!isActive)

            Spacer()

            Button(role: .destructive) {
                showRevokeConfirm = true
            } label: {
                if revoking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Revoke link", systemImage: "xmark.circle")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!isActive || revoking)
        }
    }

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

    private func iconName(for contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType.hasPrefix("video/") { return "film" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        if contentType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}
