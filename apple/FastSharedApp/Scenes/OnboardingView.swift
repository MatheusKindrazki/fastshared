import SwiftUI
import FastSharedCore

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(\.apiClient) private var apiClient
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Welcome to FastShared")
                    .font(.title.weight(.bold))
                Text("Share files to get an instant short link. We will provision this device now so you can start sharing right away.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            Spacer()
            Button {
                Task { await provision() }
            } label: {
                if isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Get started")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .disabled(isWorking)
            Spacer(minLength: 20)
        }
    }

    private func provision() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let platform = currentPlatform
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let token = try await apiClient.registerDevice(platform: platform, appVersion: version)
            let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
            let tokenStore = DeviceTokenStore(keychain: keychain)
            try await tokenStore.save(token)
            onComplete()
        } catch {
            errorMessage = "Could not register this device. \(error.localizedDescription)"
        }
    }

    private var currentPlatform: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }
}
