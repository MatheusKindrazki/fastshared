import SwiftUI
import FastSharedCore

struct SettingsView: View {
    @State private var deviceIdSuffix: String = "------"
    @State private var confirmSignOut: Bool = false
    @State private var defaultRetention: RetentionPolicy = RetentionPolicy.default

    // WHY: AppStorage doesn't reach the share-extension bundle, so we mirror into the App Group's
    // UserDefaults on every change. The share extension reads from the same suite at launch.
    private let appGroupDefaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
    private let retentionKey = "default_retention_policy"

    var body: some View {
        Form {
            Section {
                Picker("Default retention", selection: $defaultRetention) {
                    ForEach(RetentionPolicy.shareable, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .onChange(of: defaultRetention) { _, newValue in
                    appGroupDefaults?.set(newValue.rawValue, forKey: retentionKey)
                }
            } header: {
                Text("Sharing")
            } footer: {
                Text("Chooses the default link lifetime in the share sheet. You can still change it per upload.")
            }
            Section("Backend") {
                LabeledContent("API base URL", value: AppGroupConfig.apiBaseURL.absoluteString)
                LabeledContent("Short link host", value: AppGroupConfig.shortLinkHost.absoluteString)
            }
            Section("App") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Device ID", value: deviceIdSuffix)
            }
            Section {
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Text("Sign out device")
                }
            } footer: {
                Text("Removes the stored device token. A new token will be minted on the next launch.")
            }
        }
        .navigationTitle("Settings")
        .task {
            await loadDeviceId()
            loadDefaultRetention()
        }
        .confirmationDialog("Sign out this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will lose access to history on this device until you sign in again.")
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func loadDeviceId() async {
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        if let token = try? await tokenStore.load() {
            let full = token.deviceId.uuidString
            deviceIdSuffix = String(full.suffix(6))
        }
    }

    private func loadDefaultRetention() {
        if let raw = appGroupDefaults?.string(forKey: retentionKey),
           let policy = RetentionPolicy(rawValue: raw) {
            defaultRetention = policy
        } else {
            defaultRetention = .default
        }
    }

    private func signOut() async {
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        try? await tokenStore.clear()
        deviceIdSuffix = "------"
    }
}
