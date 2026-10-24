import XCTest
@testable import NeuralNotesCore

final class CloudSnapshotTests: XCTestCase {
    func testVersionRequestsAndValidatedImmutableMetadata() throws {
        let study = URL(string: "https://gateway.example/v1/study")!, id = UUID()
        let call = try CloudBackupWire.versions(studyURL: study, token: "fixture", documentID: id, offset: 50)
        XCTAssertTrue(try XCTUnwrap(call.url).absoluteString.contains("snapshots"))
        XCTAssertTrue(try XCTUnwrap(call.url).absoluteString.contains("offset=50"))
        XCTAssertThrowsError(try CloudBackupWire.versions(studyURL: study, token: "fixture", documentID: id, offset: 1))
        let download = try CloudBackupWire.download(studyURL: study, token: "fixture", documentID: id, revision: 2)
        XCTAssertTrue(try XCTUnwrap(download.url).absoluteString.contains("revision=2"))
        XCTAssertThrowsError(try CloudBackupWire.download(studyURL: study, token: "fixture", documentID: id, revision: 0))
        var row: [String: Any] = ["document_id": id.uuidString, "revision": 2, "checksum": String(repeating: "a", count: 64), "byte_size": 100,
            "created_at": "2026-10-24T10:00:00.123456+00:00"]
        func data(_ rows: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: rows) }
        let versions = try CloudBackupWire.snapshots(data([row]), documentID: id)
        XCTAssertEqual(versions.first?.revision, 2); XCTAssertNotNil(versions.first?.createdAt)
        XCTAssertThrowsError(try CloudBackupWire.snapshots(data([row, row]), documentID: id))
        XCTAssertThrowsError(try CloudBackupWire.snapshots(data([row]), documentID: UUID()))
        row["checksum"] = "bad"; XCTAssertThrowsError(try CloudBackupWire.snapshots(data([row]), documentID: id))
        row["checksum"] = String(repeating: "a", count: 64); row["byte_size"] = CloudBackupQueue.maximumBytes + 1
        XCTAssertThrowsError(try CloudBackupWire.snapshots(data([row]), documentID: id))
    }
    func testLegacyAccountPreferencesRemainOptInAndOwnerBound() throws {
        let owner = CloudBackupOwner(studyURL: URL(string: "https://gateway.example/v1/study")!, userID: UUID())
        var state = AccountSyncState(owner: owner)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        legacy.removeValue(forKey: "backupOnClose"); legacy.removeValue(forKey: "wifiOnly"); legacy.removeValue(forKey: "lastBackupAt")
        let restored = try JSONDecoder().decode(AccountSyncState.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.backupOnClose); XCTAssertNil(restored.wifiOnly)
        state.backupOnClose = true; state.wifiOnly = true; state.lastBackupAt = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(try JSONDecoder().decode(AccountSyncState.self, from: JSONEncoder().encode(state)), state)
        XCTAssertFalse(state.canResume(for: .init(studyURL: owner.studyURL, userID: UUID())))
    }
}
