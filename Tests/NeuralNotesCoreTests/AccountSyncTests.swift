import XCTest
@testable import NeuralNotesCore

final class AccountSyncTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64), changed = String(repeating: "b", count: 64)
    func testThreeWayPolicyNeverOverwritesConcurrentOrUnrelatedHistory() {
        let checkpoint = AccountSyncCheckpoint(digest: digest, revision: 7)
        XCTAssertEqual(AccountSyncPolicy.action(local: digest, remoteRevision: 7, checkpoint: checkpoint), .unchanged)
        XCTAssertEqual(AccountSyncPolicy.action(local: changed, remoteRevision: 7, checkpoint: checkpoint), .upload)
        XCTAssertEqual(AccountSyncPolicy.action(local: digest, remoteRevision: 8, checkpoint: checkpoint), .download)
        XCTAssertEqual(AccountSyncPolicy.action(local: changed, remoteRevision: 8, checkpoint: checkpoint), .conflict)
        XCTAssertEqual(AccountSyncPolicy.action(local: digest, remoteRevision: 7, checkpoint: nil), .conflict)
        XCTAssertEqual(AccountSyncPolicy.action(local: digest, remoteRevision: nil, checkpoint: nil), .upload)
        XCTAssertEqual(AccountSyncPolicy.action(local: digest, remoteRevision: nil, checkpoint: checkpoint), .conflict)
    }
    func testInterruptedUploadCheckpointsOnlyTheAcknowledgedSnapshotAndOwner() throws {
        let owner = CloudBackupOwner(studyURL: URL(string: "https://gateway.example/v1/study")!, userID: UUID())
        var state = AccountSyncState(owner: owner)
        let id = UUID(), checksum = String(repeating: "c", count: 64)
        let job = CloudBackupJob(documentID: id, title: "Fisica", archiveFile: "copy.nnbackup", checksum: checksum, bytes: 100, expectedRevision: 0)
        state.uploads[id] = AccountSyncUpload(digest: digest, archiveChecksum: checksum)
        state = try JSONDecoder().decode(AccountSyncState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(state.canResume(for: owner))
        XCTAssertFalse(state.canResume(for: CloudBackupOwner(studyURL: owner.studyURL, userID: UUID())))
        var other = job; other.checksum = changed
        state.committed(other, revision: 1); XCTAssertNil(state.checkpoints[id])
        state.committed(job, revision: 1)
        XCTAssertEqual(state.checkpoints[id], AccountSyncCheckpoint(digest: digest, revision: 1))
        XCTAssertEqual(AccountSyncPolicy.action(local: changed, remoteRevision: 1, checkpoint: state.checkpoints[id]), .upload)
        XCTAssertNil(state.uploads[id])
    }
    func testInvalidCheckpointsAreRejected() {
        XCTAssertFalse(AccountSyncCheckpoint(digest: "abc", revision: 1).isValid)
        XCTAssertFalse(AccountSyncCheckpoint(digest: digest, revision: 0).isValid)
        XCTAssertFalse(AccountSyncCheckpoint(digest: String(repeating: "ａ", count: 64), revision: 1).isValid)
    }
}
