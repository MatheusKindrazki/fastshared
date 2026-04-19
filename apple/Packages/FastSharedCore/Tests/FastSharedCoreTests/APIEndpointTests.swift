import XCTest
@testable import FastSharedCore

final class APIEndpointTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // WHY: matches the production APIClient date strategy — accept both fractional-second and plain ISO 8601.
    private let lenientDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            if let date = fractional.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date: \(raw)")
        }
        return d
    }()

    func test_presignRequest_roundTrip_with_retentionPolicy() throws {
        let original = PresignRequest(clientJobId: UUID(),
                                      contentType: "image/png",
                                      sizeBytes: 42,
                                      sha256: "deadbeef",
                                      originalFilename: "a.png",
                                      retentionPolicy: "oneHour",
                                      customTtlSeconds: nil)
        let data = try encoder.encode(original)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"retention_policy\":\"oneHour\""))
        let decoded = try decoder.decode(PresignRequest.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_presignResponse_roundTrip() throws {
        let original = PresignResponse(uploadId: "upl_1",
                                       assetId: UUID(),
                                       uploadUrl: URL(string: "https://example.com/u")!,
                                       headers: ["x-amz-acl": "private"],
                                       expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
                                       deleteAfter: Date(timeIntervalSince1970: 1_700_086_400),
                                       retentionPolicy: "oneDay",
                                       deduped: nil)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PresignResponse.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_completeRoundTrip() throws {
        let req = CompleteRequest(etag: "etag-1", sha256: "abc")
        let reqData = try encoder.encode(req)
        let reqDecoded = try decoder.decode(CompleteRequest.self, from: reqData)
        XCTAssertEqual(req, reqDecoded)

        let resp = CompleteResponse(assetId: UUID(),
                                    shortUrl: URL(string: "https://fsh.re/abc")!,
                                    token: "abc",
                                    expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
                                    deleteAfter: Date(timeIntervalSince1970: 1_700_086_400),
                                    linkStatus: "active",
                                    retentionPolicy: "oneDay")
        let respData = try encoder.encode(resp)
        let respDecoded = try decoder.decode(CompleteResponse.self, from: respData)
        XCTAssertEqual(resp, respDecoded)
    }

    func test_historyPage_roundTrip() throws {
        let item = HistoryItem(assetId: UUID(),
                               token: "abc",
                               shortUrl: URL(string: "https://fsh.re/abc")!,
                               contentType: "image/png",
                               sizeBytes: 1024,
                               originalFilename: "a.png",
                               createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                               expiresAt: Date(timeIntervalSince1970: 1_700_086_400),
                               deleteAfter: Date(timeIntervalSince1970: 1_700_172_800),
                               linkStatus: "active",
                               retentionPolicy: "oneDay",
                               accessCount: 7)
        let page = HistoryPage(items: [item], nextCursor: "cursor-2")
        let data = try encoder.encode(page)
        let decoded = try decoder.decode(HistoryPage.self, from: data)
        XCTAssertEqual(page, decoded)
    }

    func test_revokeResponse_roundTrip() throws {
        let resp = RevokeResponse(ok: true, linkStatus: "revoked", revokedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(RevokeResponse.self, from: data)
        XCTAssertEqual(resp, decoded)
    }

    func test_decoder_handles_iso8601_with_fractional_seconds() throws {
        let json = #"""
        {
          "ok": true,
          "link_status": "revoked",
          "revoked_at": "2026-04-19T10:30:45.123Z"
        }
        """#.data(using: .utf8)!
        let decoded = try lenientDecoder.decode(RevokeResponse.self, from: json)
        XCTAssertEqual(decoded.linkStatus, "revoked")
    }

    func test_decoder_handles_iso8601_without_fractional_seconds() throws {
        let json = #"""
        {
          "ok": true,
          "link_status": "revoked",
          "revoked_at": "2026-04-19T10:30:45Z"
        }
        """#.data(using: .utf8)!
        let decoded = try lenientDecoder.decode(RevokeResponse.self, from: json)
        XCTAssertEqual(decoded.linkStatus, "revoked")
    }
}
