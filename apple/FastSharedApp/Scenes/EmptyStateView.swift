import SwiftUI
import FastSharedCore

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(BrandPalette.amber.opacity(0.14))
                    .frame(width: 140, height: 140)
                    .blur(radius: 28)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(BrandPalette.amber)
            }
            VStack(spacing: 8) {
                Text("No links yet")
                    .font(.title2.weight(.semibold))
                    .tracking(-0.3)
                Text("Share anything to FastShared to get a temporary link — instantly.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            #if os(iOS)
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                Text("Open any app, tap Share, pick FastShared")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            #endif
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
