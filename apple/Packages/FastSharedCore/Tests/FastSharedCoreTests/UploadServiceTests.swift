import XCTest
import SwiftData
@testable import FastSharedCore

final class UploadServiceTests: XCTestCase {
    func test_backoff_grows_exponentially_and_caps() async {
        let orchestrator = UploadOrchestrator(apiClient: MockAPIClient(),
                                              store: SwiftDataStore.inMemoryForTests(),
                                              clipboard: NoopClipboard())
        let d1 = await orchestrator.backoffDelay(attempt: 1)
        let d2 = await orchestrator.backoffDelay(attempt: 2)
        let d5 = await orchestrator.backoffDelay(attempt: 5)
        let dHuge = await orchestrator.backoffDelay(attempt: 20)

        XCTAssertGreaterThanOrEqual(d1, 2)
        XCTAssertGreaterThan(d2, d1 - 0.5)
        XCTAssertGreaterThan(d5, d2)
        XCTAssertLessThanOrEqual(dHuge, 60 * 1.25 + 0.001)
    }

    func test_failUpload_surfaces_typed_APIError() async {
        let mock = MockAPIClient()
        mock.failUploadError = APIError.http(status: 500, problem: nil)

        do {
            try await mock.failUpload(uploadId: "upl_1", errorCode: "x", message: nil)
            XCTFail("expected throw")
        } catch let error as APIError {
            switch error {
            case .http(let status, _):
                XCTAssertEqual(status, 500)
            default:
                XCTFail("unexpected case")
            }
        } catch {
            XCTFail("not APIError: \(error)")
        }
    }

    func test_enqueue_passes_retention_policy_into_presign_body() async throws {
        let (service, mock, _, _) = try await makeService()
        mock.presignResponse = PresignResponse(uploadId: "upl_1",
                                               assetId: UUID(),
                                               uploadUrl: URL(string: "https://example.com/u")!,
                                               headers: [:],
                                               expiresAt: Date().addingTimeInterval(3600),
                                               deleteAfter: Date().addingTimeInterval(90_000),
                                               retentionPolicy: "oneHour",
                                               deduped: nil)
        let fileURL = try Self.writeTempFile(bytes: 32)
        _ = try await service.enqueue(stagedURL: fileURL,
                                      contentType: "application/octet-stream",
                                      originalFilename: "f.bin",
                                      retentionPolicy: .oneHour)
        XCTAssertEqual(mock.capturedPresignRequest?.retentionPolicy, "oneHour")
        XCTAssertNil(mock.capturedPresignRequest?.customTtlSeconds)
    }

    func test_dedupe_path_persists_share_link_and_copies_short_url() async throws {
        let (service, mock, store, clipboard) = try await makeService()
        let assetId = UUID()
        let expires = Date().addingTimeInterval(86_400)
        let deleteAfter = expires.addingTimeInterval(86_400)
        mock.presignResponse = PresignResponse(uploadId: "upl_1",
                                               assetId: UUID(),
                                               uploadUrl: URL(string: "https://example.com/u")!,
                                               headers: [:],
                                               expiresAt: expires,
                                               deleteAfter: deleteAfter,
                                               retentionPolicy: "oneDay",
                                               deduped: DedupeInfo(assetId: assetId,
                                                                   shortURL: URL(string: "https://fsh.re/abc")!,
                                                                   token: "abcDEF0123456789ABCDEF",
                                                                   expiresAt: expires,
                                                                   deleteAfter: deleteAfter,
                                                                   retentionPolicy: "oneDay"))
        let fileURL = try Self.writeTempFile(bytes: 32)
        let job = try await service.enqueue(stagedURL: fileURL,
                                            contentType: "application/octet-stream",
                                            originalFilename: "f.bin")
        XCTAssertEqual(job.status, .deduped)
        XCTAssertEqual(job.shortURL?.absoluteString, "https://fsh.re/abc")
        XCTAssertEqual(clipboard.last, "https://fsh.re/abc")

        let context = await store.mainContext()
        let entities = try context.fetch(FetchDescriptor<ShareLinkEntity>())
        let entity = try XCTUnwrap(entities.first)
        XCTAssertEqual(entity.token, "abcDEF0123456789ABCDEF")
        XCTAssertEqual(entity.expiresAt, expires)
        XCTAssertEqual(entity.deleteAfter, deleteAfter)
        XCTAssertEqual(entity.linkStatus, "active")
        XCTAssertEqual(entity.retentionPolicy, "oneDay")
    }

    func test_happy_path_schedules_background_upload_and_persists_timestamps_on_complete() async throws {
        let (service, mock, store, clipboard, orchestrator) = try await makeServiceWithOrchestrator()
        let expires = Date().addingTimeInterval(3600)
        let deleteAfter = expires.addingTimeInterval(86_400)
        let assetId = UUID()
        mock.presignResponse = PresignResponse(uploadId: "upl_42",
                                               assetId: assetId,
                                               uploadUrl: URL(string: "https://example.com/u")!,
                                               headers: ["x-amz-acl": "private"],
                                               expiresAt: expires,
                                               deleteAfter: deleteAfter,
                                               retentionPolicy: "oneHour",
                                               deduped: nil)
        mock.completeResponse = CompleteResponse(assetId: assetId,
                                                 shortUrl: URL(string: "https://fsh.re/xyz")!,
                                                 token: "tok1234567890TOKENXYZ2",
                                                 expiresAt: expires,
                                                 deleteAfter: deleteAfter,
                                                 linkStatus: "active",
                                                 retentionPolicy: "oneHour")

        let fileURL = try Self.writeTempFile(bytes: 64)
        let job = try await service.enqueue(stagedURL: fileURL,
                                            contentType: "application/octet-stream",
                                            originalFilename: "f.bin",
                                            retentionPolicy: .oneHour)
        XCTAssertEqual(job.status, .uploading)

        await orchestrator.handleTaskSuccess(clientJobId: job.clientJobId, etag: "etag-1")

        let context = await store.mainContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == "tok1234567890TOKENXYZ2" })
        let entity = try XCTUnwrap(context.fetch(descriptor).first)
        XCTAssertEqual(entity.linkStatus, "active")
        XCTAssertEqual(entity.expiresAt, expires)
        XCTAssertEqual(entity.deleteAfter, deleteAfter)
        XCTAssertEqual(entity.retentionPolicy, "oneHour")
        XCTAssertEqual(clipboard.last, "https://fsh.re/xyz")
    }

    // MARK: - helpers

    private func makeService() async throws -> (UploadService, MockAPIClient, SwiftDataStore, RecordingClipboard) {
        let result = try await makeServiceWithOrchestrator()
        return (result.0, result.1, result.2, result.3)
    }

    private func makeServiceWithOrchestrator() async throws -> (UploadService, MockAPIClient, SwiftDataStore, RecordingClipboard, UploadOrchestrator) {
        let store = SwiftDataStore.inMemoryForTests()
        let mock = MockAPIClient()
        let keychain = InMemoryKeychain()
        let tokenStore = DeviceTokenStore(keychain: keychain)
        try await tokenStore.save(DeviceToken(deviceId: UUID(), token: "t"))
        let background = RecordingBackgroundScheduler()
        let clipboard = RecordingClipboard()
        let orchestrator = UploadOrchestrator(apiClient: mock, store: store, clipboard: clipboard)
        let service = UploadService(apiClient: mock,
                                    store: store,
                                    tokenStore: tokenStore,
                                    background: background,
                                    orchestrator: orchestrator)
        return (service, mock, store, clipboard, orchestrator)
    }

    static func writeTempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = Data((0..<bytes).map { _ in UInt8.random(in: 0...255) })
        try data.write(to: url)
        return url
    }
}

// MARK: - Mocks

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var presignResponse: PresignResponse?
    var completeResponse: CompleteResponse?
    var failUploadError: Error?
    var revokeResponse: RevokeResponse?
    private(set) var capturedPresignRequest: PresignRequest?

    func registerDevice(platform: String, appVersion: String) async throws -> DeviceToken {
        DeviceToken(deviceId: UUID(), token: "mock")
    }

    func requestUpload(_ request: PresignRequest) async throws -> PresignResponse {
        capturedPresignRequest = request
        if let presignResponse { return presignResponse }
        throw APIError.transport(underlying: "no mock set")
    }

    func completeUpload(uploadId: String, request: CompleteRequest) async throws -> CompleteResponse {
        if let completeResponse { return completeResponse }
        return CompleteResponse(assetId: UUID(),
                                shortUrl: URL(string: "https://fsh.re/x")!,
                                token: "x",
                                expiresAt: Date().addingTimeInterval(3600),
                                deleteAfter: Date().addingTimeInterval(90_000),
                                linkStatus: "active",
                                retentionPolicy: "oneDay")
    }

    func failUpload(uploadId: String, errorCode: String, message: String?) async throws {
        if let failUploadError { throw failUploadError }
    }

    func fetchHistory(cursor: String?, limit: Int) async throws -> HistoryPage {
        HistoryPage(items: [], nextCursor: nil)
    }

    func deleteAsset(_ id: UUID) async throws {}

    func revokeLink(token: String) async throws -> RevokeResponse {
        if let revokeResponse { return revokeResponse }
        return RevokeResponse(ok: true, linkStatus: "revoked", revokedAt: Date())
    }

    func shortURL(forToken token: String) -> URL {
        URL(string: "https://fsh.re/s/\(token)")!
    }
}

final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func read(_ key: String) async throws -> Data? { storage[key] }
    func write(_ data: Data, for key: String) async throws { storage[key] = data }
    func delete(_ key: String) async throws { storage.removeValue(forKey: key) }
}

final class RecordingBackgroundScheduler: BackgroundSessionScheduling, @unchecked Sendable {
    struct Scheduled {
        let job: UploadJob
        let presign: PresignResponse
        let fileURL: URL
    }

    var scheduled: [Scheduled] = []

    func scheduleUpload(job: UploadJob, presign: PresignResponse, fileURL: URL) throws {
        scheduled.append(Scheduled(job: job, presign: presign, fileURL: fileURL))
    }

    func attach(completionHandler: @escaping () -> Void, identifier: String) {}
    func bind(orchestrator: UploadOrchestrator, store: SwiftDataStore) {}
}

final class RecordingClipboard: ClipboardProtocol, @unchecked Sendable {
    private(set) var last: String?
    func copy(_ string: String) { last = string }
}

extension SwiftDataStore {
    static func inMemoryForTests() -> SwiftDataStore {
        // WHY: tests must not touch the real app group container; use a dedicated in-memory store.
        SwiftDataStore(inMemory: true)
    }
}

