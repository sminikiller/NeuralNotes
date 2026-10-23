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

    func testProfileAndAccountOperationsStayOnValidatedGateway() throws {
        let study = URL(string: "https://gateway.example/prefix/v1/study")!
        XCTAssertEqual(ManagedAccountOverview.operationURL(studyURL: study, path: "account/delete")?.path, "/prefix/v1/platform/account/delete")
        XCTAssertNil(ManagedAccountOverview.operationURL(studyURL: study, path: "../auth/admin/users"))
        XCTAssertNil(ManagedAccountOverview.operationURL(studyURL: URL(string: "https://user:password@gateway.example/v1/study")!, path: "profile"))
        let value = try ManagedAccountOverview.decode(Data(#"{"profile":[{"display_name":"Lorenzo"}]}"#.utf8))
        XCTAssertEqual(value.displayName, "Lorenzo")
    }
    func testExportRejectsCrossAccountPagesAndNonAdvancingOrUnboundedCursors() throws {
        let user = UUID()
        let base: [String: Any] = ["version": 1, "userID": user.uuidString, "section": "documents", "rows": [["title": "Fisica"]], "nextOffset": NSNull()]
        let page = try ManagedAccountExportPage.decode(JSONSerialization.data(withJSONObject: base), userID: user, section: "documents", offset: 0)
        XCTAssertEqual(page.count, 1); XCTAssertNil(page.nextOffset)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: page.rows) as? [[String: String]], [["title": "Fisica"]])
        for changes: [String: Any] in [["userID": UUID().uuidString], ["section": "profile"], ["nextOffset": 0], ["nextOffset": 10], ["rows": Array(repeating: ["title": "x"], count: 11)]] {
            XCTAssertThrowsError(try ManagedAccountExportPage.decode(JSONSerialization.data(withJSONObject: base.merging(changes) { $1 }), userID: user, section: "documents", offset: 0))
        }
        let full = base.merging(["rows": Array(repeating: ["title": "x"], count: 10), "nextOffset": 10]) { $1 }
        XCTAssertEqual(try ManagedAccountExportPage.decode(JSONSerialization.data(withJSONObject: full), userID: user, section: "documents", offset: 0).nextOffset, 10)
    }

    func testStreamingExportIsValidJSONAcrossPagesAndPreservesExistingFiles() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("account-\(UUID()).json"), user = UUID()
        defer { try? FileManager.default.removeItem(at: file) }
        try await ManagedAccountExport.write(userID: user, email: "fixture@example.invalid", to: file) { section, offset in
            let count = offset == 0 ? 10 : 1
            let body: [String: Any] = ["version": 1, "userID": user.uuidString, "section": section,
                "rows": Array(repeating: ["name": "\(section) \"test\""], count: count), "nextOffset": offset == 0 ? 10 : NSNull()]
            return try JSONSerialization.data(withJSONObject: body)
        }
        let bytes = try Data(contentsOf: file)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let sections = try XCTUnwrap(json["sections"] as? [String: [[String: String]]])
        XCTAssertEqual(sections.count, ManagedAccountExportPage.sections.count); XCTAssertEqual(sections["documents"]?.count, 11)
        do { try await ManagedAccountExport.write(userID: user, email: nil, to: file) { _, _ in Data() }; XCTFail("Existing export overwritten") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testInterruptedAccountExportRemovesPartialFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("account-\(UUID()).json"), user = UUID()
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try await ManagedAccountExport.write(userID: user, email: nil, to: file) { _, _ in throw CancellationError() }
            XCTFail("Interrupted export accepted")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRejectsUnknownPlansAndInconsistentUsage() {
        for json in [#"{"entitlements":[{"plan":"gold","daily_ai_limit":1,"monthly_ai_limit":1,"storage_limit":1}]}"#,
                     #"{"entitlements":[],"usage":{"today":5,"month":2}}"#, #"{"entitlements":[],"usage":{"today":-1,"month":2}}"#, "[]"] {
            XCTAssertThrowsError(try ManagedAccountOverview.decode(Data(json.utf8)), json)
        }
    }
}
