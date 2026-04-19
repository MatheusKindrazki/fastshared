import SwiftUI
import FastSharedCore

struct ShareRootView: View {
    @Bindable var viewModel: ShareViewModel
    let onUpload: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.items.isEmpty {
                loading
            } else {
                list
            }
            Divider()
            retentionSection
            Divider()
            footer
        }
        .frame(minWidth: 360, minHeight: 340)
    }

    private var header: some View {
        HStack {
            Text("Upload to FastShared")
                .font(.headline)
            Spacer()
            if viewModel.isUploading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
    }

    private var loading: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Preparing files...")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(viewModel.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: item.contentType))
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.filename)
                                .font(.body)
                                .lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Link valid for")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Link valid for", selection: $viewModel.retentionPolicy) {
                ForEach(RetentionPolicy.shareable, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Link expires in \(viewModel.retentionPolicy.displayName). Media is deleted 24 hours later.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                Task { await onUpload() }
            } label: {
                Text("Upload")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.items.isEmpty || viewModel.isUploading)
        }
        .padding()
    }

    private func iconName(for contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType.hasPrefix("video/") { return "film" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        if contentType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}
