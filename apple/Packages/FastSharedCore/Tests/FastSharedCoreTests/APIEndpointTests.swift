import XCTest
@testable import FastSharedCore

final class APIEndpointTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // WHY: matches the production APIClient date strategy — accept both fractional-second and plain ISO 8601.
    private let lenientDecoder: JSONDecoder = {
        let d = JSONDecoder()
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
        XCTAssertTrue(json.contains("\"retentionPolicy\":\"oneHour\""), "encoded JSON missing retentionPolicy: \(json)")
        let decoded = try decoder.decode(PresignRequest.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_presignResponse_roundTrip() throws {
        let original = PresignResponse(
            uploadId: "upl_1",
            bucket: "fastshared",
            storageKey: "uploads/a/2026/04/19/abc.png",
            contentType: "image/png",
            sizeBytes: 68,
            upload: UploadInstruction(
                url: URL(string: "https://example.com/u")!,
                method: "PUT",
                headers: ["content-type": "image/png", "content-length": "68"],
                expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            retentionPolicy: "oneDay",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            deleteAfter: Date(timeIntervalSince1970: 1_700_086_400),
            deduped: nil
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PresignResponse.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_presignResponse_decodes_live_backend_happy_path() throws {
        // WHY: fixture copied from the real backend response at api.fastsha.red
        // so a future DTO drift is caught by this test, not by a failing upload.
        let json = #"""
        {
          "uploadId": "11111111-2222-3333-4444-555555555555",
          "bucket": "fastshared",
          "storageKey": "uploads/5d/2026/04/19/abc.png",
          "contentType": "image/png",
          "sizeBytes": 68,
          "upload": {
            "url": "https://fastshared.r2.cloudflarestorage.com/uploads/abc?X-Amz-Signature=x",
            "method": "PUT",
            "headers": { "content-type": "image/png", "content-length": "68" },
            "expiresAt": "2026-04-19T13:26:42.008Z"
          },
          "retentionPolicy": "oneHour",
          "expiresAt": "2026-04-19T14:11:41.731Z",
          "deleteAfter": "2026-04-20T14:11:41.731Z"
        }
        """#.data(using: .utf8)!
        let decoded = try lenientDecoder.decode(PresignResponse.self, from: json)
        XCTAssertEqual(decoded.uploadId, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(decoded.bucket, "fastshared")
        XCTAssertEqual(decoded.storageKey, "uploads/5d/2026/04/19/abc.png")
        XCTAssertEqual(decoded.contentType, "image/png")
        XCTAssertEqual(decoded.sizeBytes, 68)
        XCTAssertEqual(decoded.retentionPolicy, "oneHour")
        XCTAssertNil(decoded.deduped)
        let upload = try XCTUnwrap(decoded.upload)
        XCTAssertEqual(upload.method, "PUT")
        XCTAssertEqual(upload.headers["content-type"], "image/png")
        XCTAssertEqual(upload.headers["content-length"], "68")
    }

    func test_presignResponse_decodes_live_backend_dedup_path() throws {
        // WHY: on sha256 dedup the backend replies with ONLY `deduped`. Every other field
        // must therefore be optional on the Swift side.
        let json = #"""
        {
          "deduped": {
            "assetId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "token": "abcDEF0123456789ABCDEF",
            "shortUrl": "https://fastsha.red/s/abcDEF0123456789ABCDEF",
            "expiresAt": "2026-04-19T14:11:41.731Z",
            "deleteAfter": "2026-04-20T14:11:41.731Z",
            "retentionPolicy": "oneHour"
          }
        }
        """#.data(using: .utf8)!
        let decoded = try lenientDecoder.decode(PresignResponse.self, from: json)
        XCTAssertNil(decoded.uploadId)
        XCTAssertNil(decoded.upload)
        XCTAssertNil(decoded.bucket)
        XCTAssertNil(decoded.storageKey)
        let dedupe = try XCTUnwrap(decoded.deduped)
        XCTAssertEqual(dedupe.token, "abcDEF0123456789ABCDEF")
        XCTAssertEqual(dedupe.shortUrl.absoluteString, "https://fastsha.red/s/abcDEF0123456789ABCDEF")
        XCTAssertEqual(dedupe.retentionPolicy, "oneHour")
    }

    func test_completeRoundTrip() throws {
        let req = CompleteRequest(contentType: "image/png",
                                  sizeBytes: 68,
                                  sha256: String(repeating: "a", count: 64),
                                  originalFilename: "a.png")
        let reqData = try encoder.encode(req)
        let reqDecoded = try decoder.decode(CompleteRequest.self, from: reqData)
        XCTAssertEqual(req, reqDecoded)

        let resp = CompleteResponse(assetId: UUID(),
                                    shortUrl: URL(string: "https://fastsha.red/abc")!,
                                    token: "abc",
                                    expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
                                    deleteAfter: Date(timeIntervalSince1970: 1_700_086_400),
                                    linkStatus: "active",
                                    retentionPolicy: "oneDay")
        let respData = try encoder.encode(resp)
        let respDecoded = try decoder.decode(CompleteResponse.self, from: respData)
        XCTAssertEqual(resp, respDecoded)
    }

    func test_completeRequest_encodes_required_fields() throws {
        // WHY: backend's completeSchema requires contentType + sizeBytes (positive int).
        // This test verifies the fields are present after encoding; the key casing is
        // governed by the APIClient-wide JSONEncoder strategy.
        let req = CompleteRequest(contentType: "image/png",
                                  sizeBytes: 68,
                                  sha256: nil,
                                  originalFilename: nil)
        let data = try encoder.encode(req)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"contentType\":\"image\\/png\"") || json.contains("\"contentType\":\"image/png\""),
                      "encoded JSON missing contentType: \(json)")
        XCTAssertTrue(json.contains("\"sizeBytes\":68"), "encoded JSON missing sizeBytes: \(json)")
    }

    func test_historyPage_roundTrip() throws {
        let item = HistoryItem(assetId: UUID(),
                               token: "abc",
                               shortUrl: URL(string: "https://fastsha.red/abc")!,
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
          "linkStatus": "revoked",
          "revokedAt": "2026-04-19T10:30:45.123Z"
        }
        """#.data(using: .utf8)!
        let decoded = try lenientDecoder.decode(RevokeResponse.self, from: json)
        XCTAssertEqual(decoded.linkStatus, "revoked")
    }

    func test_decoder_handles_iso8601_without_fractional_seconds() throws {
        let json = #"""
        {
          "ok": true,
          "linkStatus": "revoked",
          "revokedAt": "2026-04-19T10:30:45Z"
        }
        """#.data(using: .utf8)!
        let decoded = try lenientDecoder.decode(RevokeResponse.self, from: json)
        XCTAssertEqual(decoded.linkStatus, "revoked")
    }
}
