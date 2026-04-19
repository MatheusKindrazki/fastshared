import XCTest
@testable import FastSharedCore

final class SHA256StreamerTests: XCTestCase {
    func test_known_content_produces_expected_hash() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        let content = "abc"
        try content.data(using: .utf8)!.write(to: url)
        let hex = try await SHA256Streamer.hash(fileAt: url)
        XCTAssertEqual(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func test_empty_file_hash() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".empty")
        try Data().write(to: url)
        let hex = try await SHA256Streamer.hash(fileAt: url)
        XCTAssertEqual(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
