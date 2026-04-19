import Foundation
@testable import FastSharedCore

/// Shared `APIClientProtocol` double for Plan B tests.
///
/// Every method has an unimplemented default that fails the test loudly — each
/// test sets only the behaviour it exercises via its `on*` closure.
final class FakeAPIClient: APIClientProtocol, @unchecked Sendable {

    // MARK: - Closure hooks

    var onVerifyIAP: (@Sendable (String) async throws -> IAPVerifyResponse)?
    var onFetchMe: (@Sendable () async throws -> MeResponse)?
    var onFetchPricingFlags: (@Sendable () async throws -> PricingFlags)?
    var onRegisterDevice: (@Sendable (String, String) async throws -> DeviceToken)?

    // MARK: - Recorded calls

    private(set) var verifyIAPCalls: [String] = []
    private(set) var fetchMeCalls: Int = 0
    private(set) var fetchPricingFlagsCalls: Int = 0
    private let lock = NSLock()

    // MARK: - APIClientProtocol

    func registerDevice(platform: String, appVersion: String) async throws -> DeviceToken {
        if let onRegisterDevice { return try await onRegisterDevice(platform, appVersion) }
        return DeviceToken(deviceId: UUID(), token: "fake")
    }

    func requestUpload(_ request: PresignRequest) async throws -> PresignResponse {
        throw APIError.transport(underlying: "unimplemented: requestUpload")
    }

    func completeUpload(uploadId: String, request: CompleteRequest) async throws -> CompleteResponse {
        throw APIError.transport(underlying: "unimplemented: completeUpload")
    }

    func failUpload(uploadId: String, errorCode: String, message: String?) async throws {
        throw APIError.transport(underlying: "unimplemented: failUpload")
    }

    func fetchHistory(cursor: String?, limit: Int) async throws -> HistoryPage {
        HistoryPage(items: [], nextCursor: nil)
    }

    func deleteAsset(_ id: UUID) async throws {
        throw APIError.transport(underlying: "unimplemented: deleteAsset")
    }

    func revokeLink(token: String) async throws -> RevokeResponse {
        throw APIError.transport(underlying: "unimplemented: revokeLink")
    }

    func shortURL(forToken token: String) -> URL {
        URL(string: "https://fastsha.red/s/\(token)")!
    }

    func verifyIAP(signedTransactionJWS: String) async throws -> IAPVerifyResponse {
        lock.lock(); verifyIAPCalls.append(signedTransactionJWS); lock.unlock()
        if let onVerifyIAP { return try await onVerifyIAP(signedTransactionJWS) }
        return IAPVerifyResponse(isPro: false, tier: nil, expiresAt: nil, caps: TierCaps.free.toDTO())
    }

    func fetchMe() async throws -> MeResponse {
        lock.lock(); fetchMeCalls += 1; lock.unlock()
        if let onFetchMe { return try await onFetchMe() }
        return MeResponse(isPro: false, tier: nil, expiresAt: nil, caps: TierCaps.free.toDTO())
    }

    func fetchPricingFlags() async throws -> PricingFlags {
        lock.lock(); fetchPricingFlagsCalls += 1; lock.unlock()
        if let onFetchPricingFlags { return try await onFetchPricingFlags() }
        return PricingFlags(earlyAccessLifetimeActive: false, earlyAccessEndsAt: nil)
    }
}
