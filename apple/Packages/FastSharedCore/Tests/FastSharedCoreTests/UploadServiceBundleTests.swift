import XCTest
import SwiftData
@testable import FastSharedCore

/// M3: bundle upload path tests. The R2 PUT step is exercised end-to-end via
/// `URLProtocol` stubbing because the bundle code path uses
/// `URLSession.upload(for:fromFile:)` directly (foreground session, not the
/// background scheduler used by single uploads).
final class UploadServiceBundleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - enqueueDrop polymorphism

    func test_enqueueDrop_singleURL_returnsSingle() async throws {
        let (service, mock, _, _) = try await makeService()
        mock.presignResponse = UploadServiceTests.makePresignHappyPath(
            uploadId: "upl_only",
            expires: Date().addingTimeInterval(3600),
            deleteAfter: Date().addingTimeInterval(90_000),
            retentionPolicy: "oneDay"
        )
        let url = try UploadServiceTests.writeTempFile(bytes: 32)
        let result = try await service.enqueueDrop(urls: [url], retentionPolicy: .oneDay)
        guard case .single = result else {
            XCTFail("expected .single, got \(result)")
            return
        }
    }

    func test_enqueueDrop_multipleURLs_returnsBundle_andMakesOneBatchCall() async throws {
        let (service, mock, _, _) = try await makeService()
        let urls = try (0..<3).map { _ in try UploadServiceTests.writeTempFile(bytes: 16) }

        let bundleToken = "bndlABCDEFGHIJKLMNOPQR"
        let bundleShortUrl = URL(string: "https://fastsha.red/b/\(bundleToken)")!
        let expires = Date().addingTimeInterval(86_400)
        mock.batchPresignBuilder = { req in
            Self.makeBatchEchoing(request: req,
                                  bundleToken: bundleToken,
                                  bundleShortUrl: bundleShortUrl,
                                  expires: expires)
        }

        // Stub the R2 PUTs so the background fan-out doesn't crash on
        // unreachable URLs. /complete uses the same mock.
        StubURLProtocol.respond(scheme: "https", host: "r2.example.com") { _ in
            (HTTPURLResponse(url: URL(string: "https://r2.example.com/x")!,
                             statusCode: 200,
                             httpVersion: nil,
                             headerFields: ["ETag": "abc"])!, Data())
        }

        let result = try await service.enqueueDrop(urls: urls, retentionPolicy: .oneDay)
        guard case .bundle(let bundle) = result else {
            XCTFail("expected .bundle, got \(result)")
            return
        }

        XCTAssertEqual(mock.batchCallCount, 1, "exactly one /uploads/batch call")
        XCTAssertEqual(mock.capturedBatchRequest?.items.count, 3)
        XCTAssertEqual(bundle.bundleToken, bundleToken)
        XCTAssertEqual(bundle.bundleShortUrl, bundleShortUrl)
        XCTAssertEqual(bundle.jobs.count, 3)
        XCTAssertEqual(bundle.totalBytes, 48)
    }

    // MARK: - aggregate progress

    func test_aggregateProgress_emitsMonotonicallyAndTerminatesAtOne() async throws {
        let (service, mock, _, _) = try await makeService()
        let urls = try (0..<2).map { _ in try UploadServiceTests.writeTempFile(bytes: 32) }

        let bundleToken = "bndlPROGRESSPROGRESS01"
        let bundleShortUrl = URL(string: "https://fastsha.red/b/\(bundleToken)")!
        let expires = Date().addingTimeInterval(86_400)
        mock.batchPresignBuilder = { req in
            Self.makeBatchEchoing(request: req,
                                  bundleToken: bundleToken,
                                  bundleShortUrl: bundleShortUrl,
                                  expires: expires)
        }

        StubURLProtocol.respond(scheme: "https", host: "r2.example.com") { _ in
            (HTTPURLResponse(url: URL(string: "https://r2.example.com/x")!,
                             statusCode: 200,
                             httpVersion: nil,
                             headerFields: nil)!, Data())
        }

        let result = try await service.enqueueDrop(urls: urls, retentionPolicy: .oneDay)
        guard case .bundle(let bundle) = result else {
            XCTFail("expected bundle")
            return
        }

        var observed: [Double] = []
        for await fraction in bundle.aggregateProgress {
            observed.append(fraction)
        }
        // Stream finishes — last value must be 1.0.
        XCTAssertFalse(observed.isEmpty, "aggregateProgress must emit at least one value")
        XCTAssertEqual(observed.last ?? 0, 1.0, accuracy: 0.001)
        // Monotonic non-decreasing.
        for i in 1..<observed.count {
            XCTAssertGreaterThanOrEqual(observed[i], observed[i - 1] - 0.0001,
                                        "aggregate progress must not regress: \(observed)")
        }
    }

    func test_partialBundleFailure_doesNotRecordBundleSuccess() async throws {
        await MainActor.run { UploadProgressMonitor.shared.dismiss() }
        let (service, mock, _, clipboard) = try await makeService()
        let urls = try (0..<3).map { _ in try UploadServiceTests.writeTempFile(bytes: 32) }

        let bundleToken = "bndlPARTIALFAILURE01"
        let bundleShortUrl = URL(string: "https://fastsha.red/b/\(bundleToken)")!
        let expires = Date().addingTimeInterval(86_400)
        mock.batchPresignBuilder = { req in
            Self.makeBatchEchoing(request: req,
                                  bundleToken: bundleToken,
                                  bundleShortUrl: bundleShortUrl,
                                  expires: expires)
        }

        StubURLProtocol.respond(scheme: "https", host: "r2.example.com") { request in
            let status = request.url?.path.contains("/put/1") == true ? 500 : 200
            return (HTTPURLResponse(url: URL(string: "https://r2.example.com/x")!,
                                    statusCode: status,
                                    httpVersion: nil,
                                    headerFields: nil)!, Data())
        }

        let result = try await service.enqueueDrop(urls: urls, retentionPolicy: .oneDay)
        guard case .bundle = result else {
            XCTFail("expected bundle")
            return
        }

        let failed = try await waitForCurrentUploadPhase(.failed)
        XCTAssertTrue(failed, "partial bundle failure should surface as failed")
        XCTAssertNil(clipboard.last, "must not copy or persist bundle link unless every item completed")
    }

    // MARK: - helpers

    /// Echoes the request items back: copies clientJobId so the service can
    /// reconcile its `metas` against the response, and synthesizes per-item
    /// uploadId + a presigned single-PUT URL pointing at the StubURLProtocol.
    static func makeBatchEchoing(request: BatchPresignRequest,
                                 bundleToken: String,
                                 bundleShortUrl: URL,
                                 expires: Date) -> BatchPresignResponse {
        let items = request.items.enumerated().map { (idx, item) -> BatchPresignItem in
            BatchPresignItem(
                clientJobId: item.clientJobId,
                uploadId: "upl_\(idx)",
                storageKey: "uploads/test/\(idx)",
                contentType: item.contentType,
                sizeBytes: item.sizeBytes,
                upload: UploadInstruction.single(.init(
                    url: URL(string: "https://r2.example.com/put/\(idx)")!,
                    method: "PUT",
                    headers: [:],
                    expiresAt: expires
                ))
            )
        }
        return BatchPresignResponse(
            bundleToken: bundleToken,
            bundleShortUrl: bundleShortUrl,
            expiresAt: expires,
            deleteAfter: expires.addingTimeInterval(86_400),
            retentionPolicy: request.retentionPolicy,
            itemCount: items.count,
            items: items
        )
    }

    private func makeService() async throws -> (UploadService, MockAPIClient, SwiftDataStore, RecordingClipboard) {
        let tracker = UsageTracker(clock: UsageTrackerTests.FakeClock("2026-04-19"),
                                   defaults: isolatedDefaults())
        let store = SwiftDataStore.inMemoryForTests()
        let mock = MockAPIClient()
        let keychain = InMemoryKeychain()
        let tokenStore = DeviceTokenStore(keychain: keychain)
        try await tokenStore.save(DeviceToken(deviceId: UUID(), token: "t"))
        let scheduler = StubBundleScheduler()
        let clipboard = RecordingClipboard()
        let orchestrator = UploadOrchestrator(apiClient: mock,
                                              store: store,
                                              clipboard: clipboard,
                                              usageTracker: tracker)
        let service = UploadService(apiClient: mock,
                                    store: store,
                                    tokenStore: tokenStore,
                                    background: scheduler,
                                    orchestrator: orchestrator,
                                    usageTracker: tracker,
                                    subscriptionStore: AlwaysProSubscriptionStore())
        return (service, mock, store, clipboard)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "dev.kindrazki.fastshared.bundle-tests.\(UUID().uuidString)"
        guard let d = UserDefaults(suiteName: name) else { return .standard }
        d.removePersistentDomain(forName: name)
        return d
    }

    private func waitForCurrentUploadPhase(_ phase: UploadProgressMonitor.ActiveUpload.Phase) async throws -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let current = await MainActor.run { UploadProgressMonitor.shared.current }
            if current?.phase == phase { return true }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}

/// Background scheduler stub whose `multipartURLSession` is wired through
/// `StubURLProtocol`, so bundle PUTs land on canned 200 responses without
/// actually hitting the network.
final class StubBundleScheduler: BackgroundSessionScheduling, @unchecked Sendable {
    var multipartURLSession: URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
    func scheduleUpload(job: UploadJob,
                        upload: UploadInstruction.SingleInstruction,
                        fileURL: URL) throws {}
    func attach(completionHandler: @escaping () -> Void, identifier: String) {}
    func bind(orchestrator: UploadOrchestrator, store: SwiftDataStore) {}
}

/// Minimal URLProtocol stub keyed on (scheme, host). Tests register a handler
/// that returns the canned response/data for matching requests.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func respond(scheme: String, host: String, _ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        handlers["\(scheme)://\(host)"] = handler
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handlers.removeAll()
    }

    private static func handler(for request: URLRequest) -> Handler? {
        guard let url = request.url, let scheme = url.scheme, let host = url.host else { return nil }
        lock.lock(); defer { lock.unlock() }
        return handlers["\(scheme)://\(host)"]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        handler(for: request) != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = StubURLProtocol.handler(for: request) else {
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
