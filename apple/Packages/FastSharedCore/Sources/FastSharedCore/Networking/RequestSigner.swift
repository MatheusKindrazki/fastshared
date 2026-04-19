import Foundation

public struct RequestSigner: Sendable {
    public let appVersion: String

    public init(appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0") {
        self.appVersion = appVersion
    }

    public func sign(_ request: inout URLRequest, token: String?) {
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        request.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
    }
}
