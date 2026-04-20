import Foundation
import OSLog

/// Tier 2: uploads a file in parallel parts against R2 presigned PUT URLs.
///
/// Kept deliberately small: reads each part's byte range off disk via
/// `FileHandle`, PUTs in a `TaskGroup` bounded to 3 concurrent slots, collects
/// ETags, and returns the completion payload the caller sends to `/complete`.
///
/// Retries per-part on transient failure (network + 5xx) up to 3 attempts with
/// exponential backoff (1s, 2s, 4s). After all retries fail the error
/// propagates up; the caller is responsible for calling the abort endpoint.
public actor MultipartUploader {
    public struct Plan: Sendable {
        public let multipartUploadId: String
        public let partSize: Int
        public let parts: [Part]

        public struct Part: Sendable {
            public let partNumber: Int
            public let url: URL

            public init(partNumber: Int, url: URL) {
                self.partNumber = partNumber
                self.url = url
            }
        }

        public init(multipartUploadId: String, partSize: Int, parts: [Part]) {
            self.multipartUploadId = multipartUploadId
            self.partSize = partSize
            self.parts = parts
        }
    }

    public struct Completion: Sendable {
        public let parts: [PartResult]

        public struct PartResult: Sendable {
            public let partNumber: Int
            public let eTag: String
        }
    }

    private let session: URLSession
    private let maxConcurrent: Int
    private let log = Logger(subsystem: Log.subsystem, category: "upload.multipart")

    public init(session: URLSession, maxConcurrent: Int = 3) {
        self.session = session
        self.maxConcurrent = maxConcurrent
    }

    /// Uploads every part of `plan` in parallel. `progress` receives a 0...1
    /// fraction and is throttled to ~4 Hz so it can be handed straight to the
    /// banner + Live Activity update paths without hammering the main actor.
    public func upload(
        fileURL: URL,
        fileSize: Int64,
        plan: Plan,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Completion {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let sizeOnDisk = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard sizeOnDisk == fileSize else {
            // Mismatch would silently truncate the last part. Fail loud.
            throw APIError.transport(underlying: "multipart file size mismatch: \(sizeOnDisk) vs \(fileSize)")
        }

        // Throttled progress: accumulator tracks completed parts (in bytes) +
        // in-flight part bytes-sent; we emit at most every 250 ms.
        let tracker = ProgressTracker(totalBytes: fileSize, emit: progress)

        var results: [Completion.PartResult] = []
        results.reserveCapacity(plan.parts.count)

        try await withThrowingTaskGroup(of: Completion.PartResult.self) { group in
            var iter = plan.parts.makeIterator()
            var inFlight = 0

            // Seed up to maxConcurrent tasks.
            while inFlight < maxConcurrent, let next = iter.next() {
                let captured = next
                group.addTask { [weak self] in
                    guard let self else {
                        throw APIError.transport(underlying: "multipart uploader deallocated")
                    }
                    return try await self.uploadPart(captured,
                                                     fileURL: fileURL,
                                                     plan: plan,
                                                     fileSize: fileSize,
                                                     tracker: tracker)
                }
                inFlight += 1
            }

            // Drain + refill as slots free up.
            while inFlight > 0 {
                do {
                    if let done = try await group.next() {
                        results.append(done)
                        inFlight -= 1
                        if let next = iter.next() {
                            let captured = next
                            group.addTask { [weak self] in
                                guard let self else {
                                    throw APIError.transport(underlying: "multipart uploader deallocated")
                                }
                                return try await self.uploadPart(captured,
                                                                 fileURL: fileURL,
                                                                 plan: plan,
                                                                 fileSize: fileSize,
                                                                 tracker: tracker)
                            }
                            inFlight += 1
                        }
                    } else {
                        break
                    }
                } catch {
                    // Cancel siblings and propagate. Caller will call abort.
                    group.cancelAll()
                    throw error
                }
            }
        }

        // Force terminal 100% emission so the banner doesn't linger at 99%.
        await tracker.flushFinal()

        // CompleteMultipartUpload requires parts sorted by PartNumber ascending.
        results.sort { $0.partNumber < $1.partNumber }
        return Completion(parts: results)
    }

    // MARK: - Internals

    private func uploadPart(_ part: Plan.Part,
                            fileURL: URL,
                            plan: Plan,
                            fileSize: Int64,
                            tracker: ProgressTracker) async throws -> Completion.PartResult {
        let offset = Int64(part.partNumber - 1) * Int64(plan.partSize)
        let remaining = fileSize - offset
        let length = Int(min(Int64(plan.partSize), remaining))
        guard length > 0 else {
            throw APIError.transport(underlying: "multipart part \(part.partNumber) has zero bytes")
        }

        let data = try readRange(fileURL: fileURL, offset: offset, length: length)

        var attempt = 0
        let maxAttempts = 3
        while true {
            attempt += 1
            do {
                let eTag = try await putPart(part: part, data: data, tracker: tracker)
                return Completion.PartResult(partNumber: part.partNumber, eTag: eTag)
            } catch {
                if attempt >= maxAttempts || !Self.isTransient(error) {
                    // Reclaim the partial credit this part was accumulating so
                    // the next retry's progress doesn't double-count bytes.
                    await tracker.drop(partNumber: part.partNumber)
                    throw error
                }
                let delayNs = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                await tracker.drop(partNumber: part.partNumber)
                log.info("part \(part.partNumber, privacy: .public) attempt \(attempt, privacy: .public) failed, retrying: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }
    }

    private func putPart(part: Plan.Part,
                         data: Data,
                         tracker: ProgressTracker) async throws -> String {
        var request = URLRequest(url: part.url)
        request.httpMethod = "PUT"
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(underlying: "multipart part \(part.partNumber) non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, problem: nil)
        }
        // URLSession's `upload(for:from:)` doesn't stream Content-Length progress
        // tick-by-tick; report the whole part as sent once it returns.
        await tracker.complete(partNumber: part.partNumber, bytes: data.count)
        guard let rawEtag = http.value(forHTTPHeaderField: "ETag") ?? http.value(forHTTPHeaderField: "Etag") else {
            throw APIError.transport(underlying: "multipart part \(part.partNumber) missing ETag header")
        }
        return Self.stripETagQuotes(rawEtag)
    }

    private func readRange(fileURL: URL, offset: Int64, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        guard let data = try handle.read(upToCount: length), data.count == length else {
            throw APIError.transport(underlying: "short read at offset \(offset)")
        }
        return data
    }

    private static func stripETagQuotes(_ etag: String) -> String {
        let trimmed = etag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func isTransient(_ error: Error) -> Bool {
        if let api = error as? APIError {
            switch api {
            case .http(let status, _):
                return status >= 500 && status < 600
            case .transport:
                return true
            default:
                return false
            }
        }
        let ns = error as NSError
        // URLError codes that typically clear on retry.
        let retryable: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorInternationalRoamingOff,
        ]
        return ns.domain == NSURLErrorDomain && retryable.contains(ns.code)
    }
}

/// Throttled cross-actor aggregator for multipart progress. Each concurrent
/// part tells the tracker when it completes so we can emit a single rolling
/// percentage to the caller's closure without hammering the main actor.
fileprivate actor ProgressTracker {
    private let totalBytes: Int64
    private let emit: @Sendable (Double) -> Void
    private var completedByPart: [Int: Int] = [:]
    private var lastEmit: Date = .distantPast
    private let minInterval: TimeInterval = 0.25

    init(totalBytes: Int64, emit: @escaping @Sendable (Double) -> Void) {
        self.totalBytes = totalBytes
        self.emit = emit
    }

    func complete(partNumber: Int, bytes: Int) {
        completedByPart[partNumber] = bytes
        maybeEmit(force: false)
    }

    func drop(partNumber: Int) {
        completedByPart.removeValue(forKey: partNumber)
    }

    func flushFinal() {
        maybeEmit(force: true)
    }

    private func maybeEmit(force: Bool) {
        let now = Date()
        let accumulated = completedByPart.values.reduce(0) { $0 + Int64($1) }
        let fraction = totalBytes > 0 ? Double(accumulated) / Double(totalBytes) : 0
        let clamped = max(0, min(1, fraction))
        if force || clamped >= 1.0 || now.timeIntervalSince(lastEmit) >= minInterval {
            lastEmit = now
            emit(clamped)
        }
    }
}
