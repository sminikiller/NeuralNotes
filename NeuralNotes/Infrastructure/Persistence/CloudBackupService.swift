import Foundation
import CryptoKit
import Observation
import NeuralNotesCore

/// Copies of closed notebooks in the student's NeuralNotes account. Each copy
/// waits in a persistent queue until the server confirms it: a lost connection,
/// a closed app or an expired reservation resume from the last completed step.
@MainActor @Observable
final class CloudBackupService {
    static let shared = CloudBackupService()
    var busy = false
    var status = ""
    var documents: [CloudDocument] = []
    private(set) var queue = CloudBackupQueue()
    private let baseFolder: URL
    private var folder: URL
    private var owner: CloudBackupOwner?
    private var resetAfterOperation = false

    init(folder: URL? = nil) {
        let base = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudBackupQueue", isDirectory: true)
        baseFolder = base; self.folder = base
        // Old queues had no owner. Keep their files for recovery, never guess an account.
        queue = CloudBackupQueue()
    }

    private func finishOperation() {
        busy = false
        if resetAfterOperation { resetAfterOperation = false; accountDidChange() }
    }
    func accountDidChange() {
        guard !busy else { resetAfterOperation = true; return }
        owner = nil; queue = CloudBackupQueue(); documents = []; status = ""
    }
    func prepareAccount() async {
        guard !busy else { return }; busy = true; defer { finishOperation() }
        do { try await selectAccount() } catch { status = message(error, title: "") }
    }

    func backup(_ book: Notebook, library: LibraryViewModel) async {
        guard !busy else { return }; busy = true; defer { finishOperation() }
        do { try await selectAccount(); try await prepare(book, library: library) } catch { status = message(error, title: book.title); return }
        await drain()
    }

    func backupAll(_ library: LibraryViewModel) async {
        guard !busy else { return }; busy = true; defer { finishOperation() }
        do { try await selectAccount() } catch { status = message(error, title: ""); return }
        var skipped: [String] = []
        for book in library.notebooks {
            if Task.isCancelled { break }
            do { try await selectAccount(); try await prepare(book, library: library) } catch { skipped.append("«\(book.title)»: \(message(error, title: book.title))") }
        }
        await drain()
        if !skipped.isEmpty { status = "Non salvati: " + skipped.prefix(3).joined(separator: " · ") + (skipped.count > 3 ? "…" : "") }
    }

    func retry() async {
        guard !busy else { return }; busy = true; defer { finishOperation() }
        do { try await selectAccount() } catch { status = message(error, title: ""); return }
        await drain()
    }

    /// The student keeps the local version: the waiting copy becomes the next cloud revision.
    func replaceCloudVersion(_ documentID: UUID) async {
        guard !busy, var job = queue.jobs.first(where: { $0.documentID == documentID }) else { return }
        busy = true; defer { finishOperation() }
        do {
            try await selectAccount()
            try await refreshDocuments()
            job.expectedRevision = documents.first(where: { $0.id == documentID })?.revision ?? job.expectedRevision
            job.replaceNewer = true; job.conflict = false; job.lastError = nil
            queue.update(job); try persist()
        } catch { status = message(error, title: job.title); return }
        await drain()
    }

    func discard(_ documentID: UUID) {
        guard !busy, let job = queue.jobs.first(where: { $0.documentID == documentID }) else { return }
        queue.drop(documentID); try? FileManager.default.removeItem(at: folder.appendingPathComponent(job.archiveFile)); try? persist()
    }

    func refresh() async {
        guard !busy else { return }; busy = true; defer { finishOperation() }
        do { try await selectAccount(); try await refreshDocuments(); status = documents.isEmpty ? "Nessuna copia nel cloud." : "\(documents.count) copie nel cloud." }
        catch { status = message(error, title: "") }
    }

    /// Downloads a cloud copy and imports it as a new notebook: local notes are never replaced.
    func downloadCopy(_ document: CloudDocument, library: LibraryViewModel) async {
        guard !busy else { return }; busy = true; defer { finishOperation() }
        do {
            try await selectAccount()
            let (service, token) = try await account()
            let (data, code) = try await exchange(CloudBackupWire.download(studyURL: service.studyURL, token: token, documentID: document.id))
            guard code == 200 else { throw CloudBackupWire.failure(status: code) }
            let file = try await downloadFile(CloudBackupWire.downloadURL(data, service: service), expectedBytes: document.bytes)
            defer { try? FileManager.default.removeItem(at: file) }
            if let checksum = document.checksum { guard try Self.sha256(file) == checksum else { throw CloudBackupFailure.invalidResponse } }
            _ = try await account()
            await library.importNotebook(from: file)
            status = library.errorMessage == nil ? "Copia di «\(document.title)» importata come nuovo quaderno." : (library.errorMessage ?? "")
        } catch { status = message(error, title: document.title) }
    }

    // MARK: Steps

    private func prepare(_ book: Notebook, library: LibraryViewModel) async throws {
        _ = try await account()
        guard EditorLeases.shared.reserveCloud(book.documentID) else { throw CloudBackupJobFailure.open }
        let archive: URL
        do {
            defer { EditorLeases.shared.releaseCloud(book.documentID) }
            archive = try await library.workspace(book).exportNative(metadata: book)
        }
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let size = Int64(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size > 0, size <= CloudBackupQueue.maximumBytes else { throw CloudBackupFailure.tooLarge }
        let checksum = try Self.sha256(archive)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(book.documentID.uuidString)-\(UUID()).nnbackup", destination = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: archive, to: destination)
        let job = CloudBackupJob(documentID: book.documentID, title: book.title, archiveFile: name, checksum: checksum, bytes: size,
                                 expectedRevision: queue.revisions[book.documentID] ?? 0)
        let previous = queue
        let replaced = try queue.enqueue(job)
        do { try persist() }
        catch { queue = previous; try? FileManager.default.removeItem(at: destination); throw error }
        if let replaced { try? FileManager.default.removeItem(at: folder.appendingPathComponent(replaced.archiveFile)) }
        status = "«\(book.title)» pronto per il cloud…"
    }

    private func drain() async {
        var saved = 0, waiting = 0
        for original in queue.jobs where !original.conflict {
            if Task.isCancelled { break }
            var job = original
            do {
                let (service, token) = try await account()
                if job.stage == .prepared {
                    status = "Prenotazione di «\(job.title)»…"
                    let (data, code) = try await exchange(CloudBackupWire.reserve(studyURL: service.studyURL, token: token, job: job))
                    _ = try await account()
                    guard code == 201 || code == 200 else { throw CloudBackupWire.failure(status: code) }
                    job.objectPath = try CloudBackupWire.reservation(data, service: service, job: job).objectPath
                    job.stage = .reserved; queue.update(job); try persist()
                }
                if job.stage == .reserved, let path = job.objectPath {
                    status = "Caricamento di «\(job.title)» · \(ByteCountFormatter.string(fromByteCount: job.bytes, countStyle: .file))…"
                    let request = try CloudBackupWire.upload(CloudBackupWire.uploadURL(service: service, objectPath: path, documentID: job.documentID), token: token, service: service)
                    let code = try await uploadFile(request, file: folder.appendingPathComponent(job.archiveFile))
                    _ = try await account()
                    switch code {
                    case 200, 201, 409: job.stage = .uploaded // 409: an earlier attempt already stored this exact object
                    case 400...499: job.stage = .prepared; job.objectPath = nil // expired or rejected reservation: reserve again
                    default: throw CloudBackupFailure.unavailable
                    }
                    queue.update(job); try persist()
                    guard job.stage == .uploaded else { throw CloudBackupFailure.unavailable }
                }
                if job.stage == .uploaded {
                    let (data, code) = try await exchange(CloudBackupWire.commit(studyURL: service.studyURL, token: token, job: job))
                    _ = try await account()
                    if code == 409 {
                        job.conflict = true; job.lastError = CloudBackupFailure.conflict.localizedDescription
                        queue.update(job); try persist(); waiting += 1; continue
                    }
                    guard code == 200 else { throw CloudBackupWire.failure(status: code) }
                    let document = try CloudBackupWire.committed(data, job: job)
                    queue.complete(job.documentID, revision: document.revision); try persist()
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(job.archiveFile))
                    documents.removeAll { $0.id == document.id }; documents.insert(document, at: 0); saved += 1
                }
            } catch {
                job.attempts += 1; job.lastError = message(error, title: job.title)
                queue.update(job); try? persist(); waiting += 1
                if error as? CloudBackupFailure == .signedOut { break }
            }
        }
        let conflicts = queue.jobs.filter(\.conflict).count
        status = (saved > 0 ? "\(saved) quaderni salvati nel cloud. " : "") + (waiting > 0 ? "\(waiting) in attesa: riprova o controlla gli avvisi." : saved == 0 && conflicts == 0 ? "Nessun backup in coda." : "")
            + (conflicts > 0 ? " \(conflicts) con una versione più recente nel cloud." : "")
    }

    private func refreshDocuments() async throws {
        let (service, token) = try await account()
        let (data, code) = try await exchange(CloudBackupWire.list(studyURL: service.studyURL, token: token))
        guard code == 200 else { throw CloudBackupWire.failure(status: code) }
        _ = try await account()
        documents = try CloudBackupWire.documents(data).filter { !$0.deleted }
    }

    // MARK: Account, files and transport

    static func storageFolder(for owner: CloudBackupOwner, under base: URL) -> URL {
        let identity = owner.studyURL.absoluteString + "\n" + owner.userID.uuidString.lowercased()
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent(key, isDirectory: true)
    }

    private func selectAccount() async throws {
        guard let current = await ManagedAIAccount.client.snapshot() else {
            owner = nil; queue = CloudBackupQueue(); documents = []; throw CloudBackupFailure.signedOut
        }
        let next = CloudBackupOwner(studyURL: current.service.studyURL, userID: current.userID)
        guard next != owner else { return }
        let target = Self.storageFolder(for: next, under: baseFolder)
        let file = target.appendingPathComponent("queue.json")
        var restored = CloudBackupQueue(owner: next)
        if FileManager.default.fileExists(atPath: file.path) {
            restored = try JSONDecoder().decode(CloudBackupQueue.self, from: Data(contentsOf: file))
            guard restored.canResume(for: next) else { throw CloudBackupFailure.invalidResponse }
        }
        restored.jobs.removeAll { !FileManager.default.fileExists(atPath: target.appendingPathComponent($0.archiveFile).path) }
        folder = target; owner = next; queue = restored; documents = []
    }

    private func account() async throws -> (service: ManagedAIService, token: String) {
        guard let current = await ManagedAIAccount.client.snapshot(),
              owner == CloudBackupOwner(studyURL: current.service.studyURL, userID: current.userID) else { throw CloudBackupFailure.signedOut }
        do {
            let authorization = try await ManagedAIAccount.client.authorization(for: current.service.studyURL)
            guard authorization.userID == current.userID else { throw CloudBackupFailure.signedOut }
            return (current.service, authorization.token)
        } catch { throw CloudBackupFailure.signedOut }
    }

    private func session(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.timeoutIntervalForResource = timeout
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    private func exchange(_ request: URLRequest) async throws -> (Data, Int) {
        let session = session(timeout: 60); defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudBackupFailure.unavailable }
        guard data.count <= 2 * 1024 * 1024 else { throw CloudBackupFailure.invalidResponse }
        return (data, http.statusCode)
    }

    private func uploadFile(_ request: URLRequest, file: URL) async throws -> Int {
        let session = session(timeout: 1800); defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.upload(for: request, fromFile: file)
        guard let http = response as? HTTPURLResponse else { throw CloudBackupFailure.unavailable }
        return http.statusCode
    }

    /// Signed links already authorize the download: no account token is sent with them.
    private func downloadFile(_ url: URL, expectedBytes: Int64) async throws -> URL {
        let session = session(timeout: 1800); defer { session.finishTasksAndInvalidate() }
        let (temporary, response) = try await session.download(for: URLRequest(url: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { try? FileManager.default.removeItem(at: temporary); throw CloudBackupFailure.unavailable }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID()).nnbackup")
        try FileManager.default.moveItem(at: temporary, to: destination)
        let size = Int64(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size == expectedBytes, size <= CloudBackupQueue.maximumBytes else { try? FileManager.default.removeItem(at: destination); throw CloudBackupFailure.invalidResponse }
        return destination
    }

    static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(queue).write(to: folder.appendingPathComponent("queue.json"), options: .atomic)
    }

    private func message(_ error: Error, title: String) -> String {
        if let failure = error as? CloudBackupJobFailure { return failure.errorDescription ?? "" }
        return error.localizedDescription
    }
}

enum CloudBackupJobFailure: LocalizedError {
    case open
    var errorDescription: String? { "Chiudi il quaderno prima di salvarlo nel cloud: gli appunti aperti vengono copiati dopo la chiusura." }
}
