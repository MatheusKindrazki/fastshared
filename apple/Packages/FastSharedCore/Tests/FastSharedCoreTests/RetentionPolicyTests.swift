import XCTest
@testable import FastSharedCore

final class RetentionPolicyTests: XCTestCase {
    func test_oneDay_ttl_is_86400() {
        XCTAssertEqual(RetentionPolicy.oneDay.ttlSeconds, 86_400)
    }

    func test_default_is_oneDay() {
        XCTAssertEqual(RetentionPolicy.default, .oneDay)
    }

    func test_all_ttls_are_reasonable() {
        XCTAssertEqual(RetentionPolicy.oneHour.ttlSeconds, 3600)
        XCTAssertEqual(RetentionPolicy.oneWeek.ttlSeconds, 604_800)
        XCTAssertEqual(RetentionPolicy.oneMonth.ttlSeconds, 2_592_000)
        XCTAssertTrue(RetentionPolicy.custom.ttlSeconds.isNaN)
    }

    func test_display_names_are_human() {
        XCTAssertEqual(RetentionPolicy.oneHour.displayName, "1 hour")
        XCTAssertEqual(RetentionPolicy.oneDay.displayName, "1 day")
        XCTAssertEqual(RetentionPolicy.oneWeek.displayName, "1 week")
        XCTAssertEqual(RetentionPolicy.oneMonth.displayName, "1 month")
        XCTAssertEqual(RetentionPolicy.custom.displayName, "Custom")
    }

    func test_shareable_excludes_custom() {
        XCTAssertEqual(RetentionPolicy.shareable, [.oneHour, .oneDay, .oneWeek, .oneMonth])
        XCTAssertFalse(RetentionPolicy.shareable.contains(.custom))
    }

    func test_shareable_cases_round_trip_through_json() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for policy in RetentionPolicy.shareable {
            let data = try encoder.encode(policy)
            let decoded = try decoder.decode(RetentionPolicy.self, from: data)
            XCTAssertEqual(policy, decoded)
        }
    }
}
