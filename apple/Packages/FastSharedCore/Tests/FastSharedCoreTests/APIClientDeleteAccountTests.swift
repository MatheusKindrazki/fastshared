import XCTest
@testable import FastSharedCore

final class APIClientDeleteAccountTests: XCTestCase {
    override func tearDown() {
        AccountDeleteURLProtocol.reset()
        super.tearDown()
    }

    func test_deleteAccountSendsBearerToken() async throws {
        let recorder = AccountDeleteRequestRecorder()
        AccountDeleteURLProtocol.respond(scheme: "https", host: "api.test") { request in
            recorder.record(request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 204,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let keychain = AccountDeleteKeychain()
        let tokenStore = DeviceTokenStore(keychain: keychain, legacyDefaults: isolatedDefaults())
        try await tokenStore.save(DeviceToken(deviceId: UUID(), token: "device-token-123"))
        let client = APIClient(
            tokenStore: tokenStore,
            session: stubbedSession(),
            baseURL: URL(string: "https://api.test")!
        )

        try await client.deleteAccount()

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/v1/account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer device-token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_deleteAccountFailsBeforeNetworkWhenTokenIsMissing() async throws {
        let recorder = AccountDeleteRequestRecorder()
        AccountDeleteURLProtocol.respond(scheme: "https", host: "api.test") { request in
            recorder.record(request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let tokenStore = DeviceTokenStore(
            keychain: AccountDeleteKeychain(),
            legacyDefaults: isolatedDefaults()
        )
        let client = APIClient(
            tokenStore: tokenStore,
            session: stubbedSession(),
            baseURL: URL(string: "https://api.test")!
        )

        do {
            try await client.deleteAccount()
            XCTFail("expected missing-token failure")
        } catch APIError.unauthorized(let detail) {
            XCTAssertEqual(detail, "missing_device_token")
        } catch {
            XCTFail("expected APIError.unauthorized, got \(error)")
        }

        XCTAssertNil(recorder.request)
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountDeleteURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "dev.kindrazki.fastshared.api-client-delete-account-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return .standard }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private final class AccountDeleteRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        value = request
    }
}

private actor AccountDeleteKeychain: KeychainStoring {
    private var storage: [String: Data] = [:]

    func read(_ key: String) async throws -> Data? {
        storage[key]
    }

    func write(_ data: Data, for key: String) async throws {
        storage[key] = data
    }

    func delete(_ key: String) async throws {
        storage.removeValue(forKey: key)
    }
}

private final class AccountDeleteURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func respond(scheme: String, host: String, _ handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers["\(scheme)://\(host)"] = handler
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    private static func handler(for request: URLRequest) -> Handler? {
        guard let url = request.url, let scheme = url.scheme, let host = url.host else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return handlers["\(scheme)://\(host)"]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        handler(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
