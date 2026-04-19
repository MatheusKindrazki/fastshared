import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text("No links yet")
                .font(.title2.weight(.semibold))
            Text("Share anything to FastShared to get a link instantly.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            #if os(iOS)
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward")
                    .rotationEffect(.degrees(45))
                Text("Tap the share icon in any app")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            #endif
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
