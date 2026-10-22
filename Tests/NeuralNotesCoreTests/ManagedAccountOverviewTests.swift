import XCTest
@testable import NeuralNotesCore

final class ManagedAccountOverviewTests: XCTestCase {
    func testAccountURLFollowsTheStudyEndpointAndPrefix() throws {
        let study = try XCTUnwrap(URL(string: "https://gateway.example/prefix/v1/study"))
        XCTAssertEqual(ManagedAccountOverview.accountURL(studyURL: study)?.absoluteString, "https://gateway.example/prefix/v1/platform/account")
        XCTAssertNil(ManagedAccountOverview.accountURL(studyURL: try XCTUnwrap(URL(string: "http://gateway.example/v1/study"))))
        XCTAssertNil(ManagedAccountOverview.accountURL(studyURL: try XCTUnwrap(URL(string: "https://gateway.example/v1/other"))))
    }

    func testDecodesPlanLimitsAndUsageWithTheStricterRemainingLimit() throws {
        let json = #"{"userID":"x","profile":[],"entitlements":[{"plan":"study","daily_ai_limit":50,"monthly_ai_limit":500,"storage_limit":2147483648}],"usage":{"day":"2026-10-22","today":12,"month":495}}"#
        let value = try ManagedAccountOverview.decode(Data(json.utf8))
        XCTAssertEqual(value.planTitle, "Studio"); XCTAssertEqual(value.usedToday, 12); XCTAssertEqual(value.usedThisMonth, 495)
        XCTAssertEqual(value.remaining, 5); XCTAssertEqual(value.storageLimit, 2_147_483_648)
        let fresh = try ManagedAccountOverview.decode(Data(#"{"entitlements":[]}"#.utf8))
        XCTAssertEqual(fresh.planTitle, "Base"); XCTAssertEqual(fresh.remaining, 10)
    }

    func testRejectsUnknownPlansAndInconsistentUsage() {
        for json in [#"{"entitlements":[{"plan":"gold","daily_ai_limit":1,"monthly_ai_limit":1,"storage_limit":1}]}"#,
                     #"{"entitlements":[],"usage":{"today":5,"month":2}}"#, #"{"entitlements":[],"usage":{"today":-1,"month":2}}"#, "[]"] {
            XCTAssertThrowsError(try ManagedAccountOverview.decode(Data(json.utf8)), json)
        }
    }
}
