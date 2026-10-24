import XCTest
import SwiftData
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class AccountNotebookSyncTests: XCTestCase {
    @MainActor func testTwoDevicesUploadDownloadAndDetectConcurrentEditsWithoutReplacingThem() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = AccountCloudFixture(), auth = try await server.client()
        let first = try library(root.appendingPathComponent("first")), second = try library(root.appendingPathComponent("second"))
        let book = try first.repository.createNotebook(title: "Fisica", folderID: nil, cover: .lagoon)
        try first.model.reload(); try await write("Prima versione", book: book, library: first.model)
        let a = service(root.appendingPathComponent("queue-a"), auth, server)
        let b = service(root.appendingPathComponent("queue-b"), auth, server)
        await a.synchronize(first.model)
        XCTAssertTrue(a.queue.jobs.isEmpty, a.status)
        let uploads = await server.uploadCount; XCTAssertEqual(uploads, 1)
        await a.synchronize(first.model)
        let unchanged = await server.uploadCount; XCTAssertEqual(unchanged, 1, "No upload for an unchanged package")
        await b.synchronize(second.model)
        let received = try XCTUnwrap(second.model.notebooks.first, b.status)
        XCTAssertEqual(received.id, book.id); XCTAssertEqual(received.documentID, book.documentID)
        let receivedText = try await text(received, library: second.model); XCTAssertEqual(receivedText, "Prima versione")
        await b.backup(received, library: second.model)
        XCTAssertTrue(b.queue.jobs.isEmpty, "Manual backup must use the revision received by synchronization: \(b.status)")
        try await write("Aggiornamento da B", book: received, library: second.model)
        await b.synchronize(second.model); await a.synchronize(first.model)
        let updated = try await text(book, library: first.model); XCTAssertEqual(updated, "Aggiornamento da B", a.status)
        let backups = try await first.model.workspace(book).automaticBackups(); XCTAssertFalse(backups.isEmpty)
        try await write("Locale A", book: book, library: first.model)
        try await write("Locale B", book: received, library: second.model)
        await a.synchronize(first.model); await b.synchronize(second.model)
        XCTAssertNotNil(b.conflicts[book.documentID], b.status)
        let untouched = try await text(received, library: second.model); XCTAssertEqual(untouched, "Locale B")
        await b.resolve(book.documentID, keepingLocal: false, library: second.model)
        XCTAssertTrue(b.conflicts.isEmpty, b.status)
        let resolved = try await text(received, library: second.model); XCTAssertEqual(resolved, "Locale A")
    }

    @MainActor func testInterruptedUploadResumesAfterRestartAndCorruptDownloadIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = AccountCloudFixture(), auth = try await server.client()
        let local = try library(root.appendingPathComponent("local"))
        let book = try local.repository.createNotebook(title: "Duraturo", folderID: nil, cover: .sand)
        try local.model.reload(); try await write("Senza perdita", book: book, library: local.model)
        await server.failNextUpload()
        let folder = root.appendingPathComponent("queue")
        let interrupted = service(folder, auth, server)
        await interrupted.synchronize(local.model)
        XCTAssertEqual(interrupted.queue.jobs.first?.stage, .reserved)
        let resumed = service(folder, auth, server)
        await resumed.synchronize(local.model)
        XCTAssertTrue(resumed.queue.jobs.isEmpty, resumed.status)
        let count = await server.uploadCount; XCTAssertEqual(count, 1)
        // The persisted snapshot fingerprint prevents a redundant re-upload.
        await resumed.synchronize(local.model)
        let repeated = await server.uploadCount; XCTAssertEqual(repeated, 1)
        let fresh = try library(root.appendingPathComponent("fresh"))
        await server.corruptDownloads()
        let download = service(root.appendingPathComponent("download"), auth, server)
        await download.synchronize(fresh.model)
        XCTAssertTrue(fresh.model.notebooks.isEmpty)
        XCTAssertTrue(download.status.contains("Avvisi"), download.status)
        let source = try await text(book, library: local.model); XCTAssertEqual(source, "Senza perdita")
    }

    @MainActor func testOpenNotebookIsSkippedAndAutomaticPreferenceSurvivesRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = AccountCloudFixture(), auth = try await server.client()
        let local = try library(root.appendingPathComponent("local"))
        let book = try local.repository.createNotebook(title: "Aperto", folderID: nil, cover: .lagoon)
        try local.model.reload()
        let editor = EditorViewModel(workspace: try local.model.workspace(book)); await editor.open()
        let folder = root.appendingPathComponent("queue"), cloud = service(folder, auth, server)
        await cloud.synchronize(local.model)
        let skipped = await server.uploadCount; XCTAssertEqual(skipped, 0)
        let closed = await editor.close(); XCTAssertTrue(closed)
        await cloud.synchronize(local.model) // explicit consent to associate the local notebook
        await cloud.setAutomatic(true)
        _ = try local.repository.createNotebook(title: "Nuovo · non associato", folderID: nil, cover: .sand)
        try local.model.reload()
        let restarted = service(folder, auth, server)
        await restarted.synchronizeIfEnabled(local.model)
        XCTAssertTrue(restarted.automatic)
        let uploaded = await server.uploadCount; XCTAssertEqual(uploaded, 1)
        XCTAssertEqual(restarted.documents.count, 1, "Returning to an account must not silently upload other local notebooks")
        await restarted.synchronize(local.model) // the explicit command can enroll the new notebook
        let adopted = await server.uploadCount; XCTAssertEqual(adopted, 2)
    }

    @MainActor func testCloudIndexReadsBeyondTheFirstFiftyNotebooks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = AccountCloudFixture(), auth = try await server.client()
        await server.seedIndex(count: 75)
        let cloud = service(root, auth, server)
        await cloud.refresh()
        XCTAssertEqual(cloud.documents.count, 75, cloud.status)
        XCTAssertEqual(Set(cloud.documents.map(\.id)).count, 75)
    }

    @MainActor private func library(_ root: URL) throws -> (repository: SwiftDataLibraryRepository, model: LibraryViewModel) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let config = ModelConfiguration("SyncTest", schema: schema, url: root.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [config])
        let repository = SwiftDataLibraryRepository(container: container, documents: try NativeDocumentStore(root: root.appendingPathComponent("Notebooks")))
        let model = LibraryViewModel(repository: repository); try model.reload()
        return (repository, model)
    }
    @MainActor private func service(_ folder: URL, _ auth: ManagedAIClient, _ server: AccountCloudFixture) -> CloudBackupService {
        CloudBackupService(folder: folder, client: auth, transport: { try await server.send($0) },
            fileUpload: { try await server.upload($0, file: $1) }, fileDownload: { try await server.download($0) })
    }
    @MainActor private func write(_ text: String, book: Notebook, library: LibraryViewModel) async throws {
        let workspace = try library.workspace(book)
        let pages = try await workspace.pages()
        var page: PageSnapshot
        if let first = pages.first { page = first }
        else { page = try await workspace.addDefaultPage() }
        page.texts = [TextElement(text: text)]; page.revision += 1
        _ = try await workspace.save(page, drawing: PKDrawing().dataRepresentation())
    }
    @MainActor private func text(_ book: Notebook, library: LibraryViewModel) async throws -> String? {
        try await library.workspace(book).pages().first?.texts.first?.text
    }
}

private actor AccountCloudFixture: ManagedAITransport {
    let user = UUID()
    var rows: [UUID: CloudDocument] = [:], objects: [String: Data] = [:], paths: [UUID: String] = [:]
    var uploadCount = 0
    private var failUpload = false, corrupt = false
    func failNextUpload() { failUpload = true }
    func corruptDownloads() { corrupt = true }
    func seedIndex(count: Int) {
        for i in 0..<count {
            let id = UUID()
            rows[id] = CloudDocument(id: id, revision: 1, title: "Quaderno \(i)", checksum: String(repeating: "a", count: 64), bytes: 1, deleted: false, updatedAt: nil)
        }
    }
    func client() throws -> ManagedAIClient {
        let config = Data(#"{"version":1,"managed":true,"auth":{"url":"https://project.example","publicKey":"sb_publishable_fixture_only"}}"#.utf8)
        let service = try ManagedAIService.decode(config, studyURL: URL(string: "https://gateway.example/v1/study")!)
        let bytes = try JSONSerialization.data(withJSONObject: ["access_token": "fixture-access", "refresh_token": "fixture-refresh", "token_type": "bearer", "expires_in": 3600,
            "user": ["id": user.uuidString, "email": "test@example.invalid", "is_anonymous": false]])
        return ManagedAIClient(transport: self, storage: AccountCloudSession(try ManagedAISession.decode(bytes, service: service, now: Date())))
    }
    func send(_ request: URLRequest) async throws -> ManagedAIHTTPResponse {
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data("{}".utf8)) as? [String: Any] ?? [:]
        func reply(_ object: Any, _ status: Int = 200) throws -> ManagedAIHTTPResponse {
            ManagedAIHTTPResponse(data: try JSONSerialization.data(withJSONObject: object), status: status)
        }
        let url = try XCTUnwrap(request.url)
        switch url.lastPathComponent {
        case "documents":
            let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value.flatMap(Int.init) ?? 0
            let batch = rows.values.sorted { $0.id.uuidString < $1.id.uuidString }.dropFirst(offset).prefix(50)
            return ManagedAIHTTPResponse(data: try JSONEncoder().encode(Array(batch)), status: 200)
        case "uploads":
            let id = try XCTUnwrap(body["entityID"] as? String)
            let path = "\(user.uuidString.lowercased())/cloud/\(id)/\(UUID().uuidString.lowercased()).nnbackup"
            return try reply(["objectPath": path, "method": "POST", "publicKey": "sb_publishable_fixture_only", "expectedBytes": body["bytes"] ?? 0,
                "requiresUserBearer": true, "upsert": false, "uploadURL": "https://project.example/storage/v1/object/neuralnotes-private/" + path], 201)
        case "commit":
            let id = try XCTUnwrap((body["documentID"] as? String).flatMap(UUID.init(uuidString:)))
            let revision = try XCTUnwrap(body["expectedRevision"] as? Int)
            guard (rows[id]?.revision ?? 0) == revision else { return try reply([:], 409) }
            let path = try XCTUnwrap(body["objectPath"] as? String)
            guard objects[path] != nil else { return try reply([:], 400) }
            let row = CloudDocument(id: id, revision: revision + 1, title: body["title"] as? String ?? "", checksum: body["checksum"] as? String,
                bytes: Int64(body["bytes"] as? Int ?? 0), deleted: false, updatedAt: nil)
            rows[id] = row; paths[id] = path
            return ManagedAIHTTPResponse(data: try JSONEncoder().encode(row), status: 200)
        case "download":
            let id = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value.flatMap(UUID.init(uuidString:)))
            let path = try XCTUnwrap(paths[id])
            return try reply(["url": "https://project.example/storage/v1/object/sign/neuralnotes-private/" + path + "?token=fixture", "expiresIn": 60])
        default: return try reply([:], 404)
        }
    }
    func upload(_ request: URLRequest, file: URL) throws -> Int {
        if failUpload { failUpload = false; throw CloudBackupFailure.unavailable }
        let path = try XCTUnwrap(request.url?.path.components(separatedBy: "/neuralnotes-private/").last)
        objects[path] = try Data(contentsOf: file); uploadCount += 1; return 201
    }
    func download(_ url: URL) throws -> URL {
        let path = try XCTUnwrap(url.path.components(separatedBy: "/neuralnotes-private/").last)
        var bytes = try XCTUnwrap(objects[path]); if corrupt { bytes[0] ^= 255 }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID()).nnbackup")
        try bytes.write(to: file); return file
    }
}
private final class AccountCloudSession: ManagedAISessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ManagedAISession?
    init(_ value: ManagedAISession) { self.value = value }
    func load() throws -> ManagedAISession? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ session: ManagedAISession?) throws { lock.lock(); defer { lock.unlock() }; value = session }
}
