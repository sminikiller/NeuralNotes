import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NeuralNotesCore

final class CloudBackupTests: XCTestCase {
    private let study = URL(string: "https://gateway.example/api/v1/study")!
    private let service = ManagedAIService(studyURL: URL(string: "https://gateway.example/api/v1/study")!, authURL: URL(string: "https://project.supabase.example")!, publicKey: "sb_publishable_fixture-key")
    private let document = UUID(), owner = UUID(), object = UUID()
    private let checksum = String(repeating: "ab", count: 32)
    private func job(_ bytes: Int64 = 2048) -> CloudBackupJob {
        CloudBackupJob(documentID: document, title: "Fisica\n1", archiveFile: "\(document).nnbackup", checksum: checksum, bytes: bytes, expectedRevision: 3)
    }
    private var objectPath: String { "\(owner.uuidString.lowercased())/cloud/\(document.uuidString.lowercased())/\(object.uuidString.lowercased()).nnbackup" }
    private func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }

    func testQueuesNeverResumeForAnotherAccountGatewayOrUnidentifiedLegacyArchive() throws {
        let first = CloudBackupOwner(studyURL: study, userID: owner)
        var queue = CloudBackupQueue(owner: first); try queue.enqueue(job())
        let restored = try JSONDecoder().decode(CloudBackupQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertTrue(restored.canResume(for: first))
        XCTAssertFalse(restored.canResume(for: CloudBackupOwner(studyURL: study, userID: UUID())))
        XCTAssertFalse(restored.canResume(for: CloudBackupOwner(studyURL: URL(string: "https://another.example/v1/study")!, userID: owner)))
        var legacy = CloudBackupQueue(); try legacy.enqueue(job())
        let old = try JSONDecoder().decode(CloudBackupQueue.self, from: JSONEncoder().encode(legacy))
        XCTAssertFalse(old.canResume(for: first)); XCTAssertEqual(old.jobs.count, 1)
    }

    func testQueueReplacesOlderCopiesAndRejectsOversizedArchives() throws {
        var queue = CloudBackupQueue()
        XCTAssertNil(try queue.enqueue(job()))
        var newer = job(4096); newer.title = "Fisica"
        XCTAssertEqual(try queue.enqueue(newer)?.bytes, 2048); XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertThrowsError(try queue.enqueue(job(CloudBackupQueue.maximumBytes + 1))) { XCTAssertEqual($0 as? CloudBackupFailure, .tooLarge) }
        queue.complete(document, revision: 4)
        XCTAssertTrue(queue.jobs.isEmpty); XCTAssertEqual(queue.revisions[document], 4)
        let restored = try JSONDecoder().decode(CloudBackupQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(restored, queue); XCTAssertEqual(job().title, "Fisica 1")
    }

    func testReserveUploadAndCommitCarryOnlyTheirOwnFields() throws {
        let reserve = try CloudBackupWire.reserve(studyURL: study, token: "user-token", job: job())
        XCTAssertEqual(reserve.url?.absoluteString, "https://gateway.example/api/v1/platform/uploads")
        XCTAssertEqual(reserve.value(forHTTPHeaderField: "Authorization"), "Bearer user-token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(reserve.httpBody)) as? [String: Any])
        XCTAssertEqual(body["kind"] as? String, "cloud"); XCTAssertEqual(body["bytes"] as? Int, 2048); XCTAssertEqual(body["entityID"] as? String, document.uuidString.lowercased())
        let upload = URL(string: "https://project.supabase.example/storage/v1/object/neuralnotes-private/\(objectPath)")!
        let reply = try data(["objectPath": objectPath, "method": "POST", "uploadURL": upload.absoluteString, "publicKey": service.publicKey, "expectedBytes": 2048, "requiresUserBearer": true, "upsert": false])
        let reservation = try CloudBackupWire.reservation(reply, service: service, job: job())
        XCTAssertEqual(reservation.objectPath, objectPath)
        XCTAssertEqual(try CloudBackupWire.uploadURL(service: service, objectPath: objectPath, documentID: document), reservation.uploadURL)
        XCTAssertThrowsError(try CloudBackupWire.uploadURL(service: service, objectPath: "../\(objectPath)", documentID: document))
        XCTAssertFalse(job().conflict)
        let put = try CloudBackupWire.upload(reservation.uploadURL, token: "user-token", service: service)
        XCTAssertEqual(put.value(forHTTPHeaderField: "x-upsert"), "false"); XCTAssertEqual(put.value(forHTTPHeaderField: "apikey"), service.publicKey)
        XCTAssertEqual(put.httpMethod, "POST"); XCTAssertNil(put.httpBody)
        var uploaded = job(); uploaded.stage = .uploaded; uploaded.objectPath = objectPath
        let commit = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(CloudBackupWire.commit(studyURL: study, token: "user-token", job: uploaded).httpBody)) as? [String: Any])
        XCTAssertEqual(commit["expectedRevision"] as? Int, 3); XCTAssertEqual(commit["objectPath"] as? String, objectPath); XCTAssertEqual(commit["deleted"] as? Bool, false)
        XCTAssertThrowsError(try CloudBackupWire.commit(studyURL: study, token: "user-token", job: job()))
        XCTAssertThrowsError(try CloudBackupWire.reserve(studyURL: study, token: "", job: job()))
    }

    func testReservationsAndDownloadsNeverLeaveTheConfiguredHosts() throws {
        func reply(_ changes: [String: Any]) throws -> Data {
            var value: [String: Any] = ["objectPath": objectPath, "method": "POST", "publicKey": service.publicKey, "expectedBytes": 2048, "requiresUserBearer": true, "upsert": false,
                                        "uploadURL": "https://project.supabase.example/storage/v1/object/neuralnotes-private/\(objectPath)"]
            value.merge(changes) { $1 }; return try data(value)
        }
        for change: [String: Any] in [["uploadURL": "https://evil.example/storage/v1/object/neuralnotes-private/\(objectPath)"],
                                      ["uploadURL": "http://project.supabase.example/storage/v1/object/neuralnotes-private/\(objectPath)"],
                                      ["uploadURL": "https://project.supabase.example/storage/v1/object/public/\(objectPath)"],
                                      ["objectPath": "\(owner.uuidString.lowercased())/cloud/\(UUID().uuidString.lowercased())/\(object.uuidString.lowercased()).nnbackup"],
                                      ["objectPath": "\(owner.uuidString.lowercased())/community/\(document.uuidString.lowercased())/x.nnbackup"],
                                      ["upsert": true], ["expectedBytes": 9], ["publicKey": "other"], ["requiresUserBearer": false]] {
            XCTAssertThrowsError(try CloudBackupWire.reservation(reply(change), service: service, job: job()), "\(change)")
        }
        let signed = "https://project.supabase.example/storage/v1/object/sign/neuralnotes-private/\(objectPath)?token=abc"
        XCTAssertEqual(try CloudBackupWire.downloadURL(data(["url": signed, "expiresIn": 60]), service: service).absoluteString, signed)
        XCTAssertThrowsError(try CloudBackupWire.downloadURL(data(["url": "https://other.example/storage/v1/object/sign/neuralnotes-private/x", "expiresIn": 60]), service: service))
        XCTAssertThrowsError(try CloudBackupWire.downloadURL(data(["url": signed, "expiresIn": 0]), service: service))
        let download = try CloudBackupWire.download(studyURL: study, token: "t", documentID: document)
        XCTAssertEqual(download.url?.absoluteString, "https://gateway.example/api/v1/platform/download?document=\(document.uuidString.lowercased())")
    }

    func testCommittedRevisionAndDocumentListAreValidated() throws {
        var uploaded = job(); uploaded.stage = .uploaded; uploaded.objectPath = objectPath
        let row: [String: Any] = ["id": document.uuidString.lowercased(), "owner_id": owner.uuidString.lowercased(), "revision": 4, "title": "Fisica 1", "object_path": objectPath,
                                  "checksum": checksum, "byte_size": 2048, "deleted": false, "updated_at": "2026-10-22T15:04:05.123456+00:00"]
        let value = try CloudBackupWire.committed(data(row), job: uploaded)
        XCTAssertEqual(value.revision, 4); XCTAssertNotNil(value.updatedAt)
        for change: [String: Any] in [["revision": 7], ["checksum": String(repeating: "cd", count: 32)], ["byte_size": 1], ["id": UUID().uuidString]] {
            XCTAssertThrowsError(try CloudBackupWire.committed(data(row.merging(change) { $1 }), job: uploaded))
        }
        let list = try CloudBackupWire.documents(data([row, row.merging(["id": UUID().uuidString, "updated_at": "2026-10-22T15:04:05Z", "checksum": NSNull()]) { $1 }]))
        XCTAssertEqual(list.count, 2); XCTAssertNotNil(list[1].updatedAt); XCTAssertNil(list[1].checksum)
        XCTAssertThrowsError(try CloudBackupWire.documents(data([row.merging(["byte_size": CloudBackupQueue.maximumBytes + 1]) { $1 }])))
        XCTAssertEqual(CloudBackupWire.failure(status: 409), .conflict); XCTAssertEqual(CloudBackupWire.failure(status: 503), .unavailable)
    }
}
