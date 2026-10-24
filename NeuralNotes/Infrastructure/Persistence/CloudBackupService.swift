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
    private(set) var conflicts: [UUID: CloudDocument] = [:]
    private var syncState: AccountSyncState?
    private let baseFolder: URL
    private var folder: URL
    private var owner: CloudBackupOwner?
    private var resetAfterOperation = false
    private var operationOwner: CloudBackupOwner?
    @ObservationIgnored private let client: ManagedAIClient
    @ObservationIgnored private let transport: (@Sendable (URLRequest) async throws -> ManagedAIHTTPResponse)?
    @ObservationIgnored private let fileUpload: (@Sendable (URLRequest, URL) async throws -> Int)?
    @ObservationIgnored private let fileDownload: (@Sendable (URL) async throws -> URL)?
    @ObservationIgnored private let automaticNetwork: @MainActor () -> Bool
    @ObservationIgnored private var pendingClosures: [(Notebook, LibraryViewModel, CloudBackupOwner)] = []

    init(folder: URL? = nil, client: ManagedAIClient? = nil,
         transport: (@Sendable (URLRequest) async throws -> ManagedAIHTTPResponse)? = nil,
         fileUpload: (@Sendable (URLRequest, URL) async throws -> Int)? = nil,
         fileDownload: (@Sendable (URL) async throws -> URL)? = nil,
         automaticNetwork: (@MainActor () -> Bool)? = nil) {
        self.client = client ?? ManagedAIAccount.client; self.transport = transport
        self.fileUpload = fileUpload; self.fileDownload = fileDownload
        self.automaticNetwork = automaticNetwork ?? { CloudNetworkMonitor.shared.unmeteredWiFi }
        let base = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudBackupQueue", isDirectory: true)
        baseFolder = base; self.folder = base
        // Old queues had no owner. Keep their files for recovery, never guess an account.
        queue = CloudBackupQueue()
    }

    private func finishOperation() {
        busy = false; operationOwner = nil
        if resetAfterOperation { resetAfterOperation = false; accountDidChange() }
        if !pendingClosures.isEmpty {
            let pending = pendingClosures.removeFirst()
            Task { await notebookClosed(pending.0, library: pending.1, expectedOwner: pending.2) }
        }
    }
    func accountDidChange() {
        guard !busy else { resetAfterOperation = true; return }
        owner = nil; queue = CloudBackupQueue(); documents = []; conflicts = [:]; syncState = nil; status = ""
        pendingClosures = []
    }
    func prepareAccount() async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do { try await selectAccount() } catch { status = message(error, title: "") }
    }

    func backup(_ book: Notebook, library: LibraryViewModel) async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do { try await selectAccount(); try await prepare(book, library: library) } catch { status = message(error, title: book.title); return }
        await drain()
    }

    func backupAll(_ library: LibraryViewModel) async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do { try await selectAccount() } catch { status = message(error, title: ""); return }
        var skipped: [String] = []
        for book in library.notebooks {
            if Task.isCancelled { break }
            do { try await prepare(book, library: library) } catch { skipped.append("«\(book.title)»: \(message(error, title: book.title))"); if error as? CloudBackupFailure == .signedOut { break } }
        }
        await drain()
        if !skipped.isEmpty { status = "Non salvati: " + skipped.prefix(3).joined(separator: " · ") + (skipped.count > 3 ? "…" : "") }
    }

    func retry() async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do { try await selectAccount() } catch { status = message(error, title: ""); return }
        await drain()
    }

    /// The student keeps the local version: the waiting copy becomes the next cloud revision.
    func replaceCloudVersion(_ documentID: UUID) async {
        guard !busy else { return }
        let expectedOwner = owner
        busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount()
            guard expectedOwner == owner else { throw CloudBackupFailure.signedOut }
            guard var job = queue.jobs.first(where: { $0.documentID == documentID }) else { return }
            try await refreshDocuments()
            job.expectedRevision = documents.first(where: { $0.id == documentID })?.revision ?? job.expectedRevision
            job.replaceNewer = true; job.conflict = false; job.lastError = nil
            queue.update(job); try persist()
        } catch { status = message(error, title: ""); return }
        await drain()
    }

    func discard(_ documentID: UUID) async {
        guard !busy else { return }
        let expectedOwner = owner
        busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount()
            guard expectedOwner == owner else { throw CloudBackupFailure.signedOut }
            guard let job = queue.jobs.first(where: { $0.documentID == documentID }) else { return }
            let previous = queue; queue.drop(documentID)
            do { try persist() } catch { queue = previous; throw error }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(job.archiveFile))
        } catch { status = message(error, title: "") }
    }

    func refresh() async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do { try await selectAccount(); try await refreshDocuments(); status = documents.isEmpty ? "Nessuna copia nel cloud." : "\(documents.count) copie nel cloud." }
        catch { status = message(error, title: "") }
    }

    /// Downloads a cloud copy and imports it as a new notebook: local notes are never replaced.
    func downloadCopy(_ document: CloudDocument, library: LibraryViewModel, revision: Int? = nil) async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount()
            let (service, token) = try await account()
            let (data, code) = try await exchange(CloudBackupWire.download(studyURL: service.studyURL, token: token, documentID: document.id, revision: revision))
            guard code == 200 else { throw CloudBackupWire.failure(status: code) }
            let file = try await downloadFile(CloudBackupWire.downloadURL(data, service: service), expectedBytes: document.bytes)
            defer { try? FileManager.default.removeItem(at: file) }
            if let checksum = document.checksum {
                let actual = try await Task.detached(priority: .utility) { try Self.sha256(file) }.value
                guard actual == checksum else { throw CloudBackupFailure.invalidResponse }
            }
            _ = try await account()
            await library.importNotebook(from: file)
            status = library.errorMessage == nil ? "Copia di «\(document.title)» importata come nuovo quaderno." : (library.errorMessage ?? "")
        } catch { status = message(error, title: document.title) }
    }

    var automatic: Bool { syncState?.automatic ?? false }
    var backupOnClose: Bool { syncState?.backupOnClose ?? false }
    var wifiOnly: Bool { syncState?.wifiOnly ?? false }
    var lastBackupAt: Date? { syncState?.lastBackupAt }
    var accountConnected: Bool { owner != nil }

    func setBackupPreferences(onClose: Bool, wifiOnly: Bool) async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount(); syncState?.backupOnClose = onClose; syncState?.wifiOnly = wifiOnly; try persistSyncState()
        } catch { status = message(error, title: "") }
    }

    /// This switch only covers notebooks explicitly enrolled in the current account.
    /// A login change must never silently upload another student's local notebooks.
    func notebookClosed(_ book: Notebook, library: LibraryViewModel, expectedOwner: CloudBackupOwner? = nil) async {
        guard let current = await client.snapshot() else { return }
        let closingOwner = CloudBackupOwner(studyURL: current.service.studyURL, userID: current.userID)
        guard expectedOwner == nil || expectedOwner == closingOwner else { return }
        if busy {
            pendingClosures.removeAll { $0.0.documentID == book.documentID }
            pendingClosures.append((book, library, closingOwner)); return
        }
        busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount()
            guard owner == closingOwner, backupOnClose, syncState?.checkpoints[book.documentID] != nil else { return }
            try await prepare(book, library: library)
            guard !wifiOnly || automaticNetwork() else { status = "Backup pronto: in attesa di Wi-Fi senza risparmio dati."; return }
            await drain()
        } catch { status = message(error, title: book.title) }
    }

    func versions(_ document: CloudDocument) async -> [CloudSnapshot] {
        guard !busy else { return [] }; busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount(); var collected: [Int: CloudSnapshot] = [:]
            for offset in stride(from: 0, through: 10_000, by: 50) {
                let (service, token) = try await account()
                let (data, code) = try await exchange(CloudBackupWire.versions(studyURL: service.studyURL, token: token, documentID: document.id, offset: offset))
                guard code == 200 else { throw CloudBackupWire.failure(status: code) }
                _ = try await account()
                let batch = try CloudBackupWire.snapshots(data, documentID: document.id)
                for value in batch {
                    if let previous = collected[value.revision], previous != value { throw CloudBackupFailure.conflict }
                    collected[value.revision] = value
                }
                if batch.count < 50 { return collected.values.sorted { $0.revision > $1.revision } }
            }
            throw CloudBackupFailure.invalidResponse
        } catch { status = message(error, title: document.title); return [] }
    }

    func downloadVersion(_ snapshot: CloudSnapshot, title: String, library: LibraryViewModel) async {
        let document = CloudDocument(id: snapshot.documentID, revision: snapshot.revision, title: title,
            checksum: snapshot.checksum, bytes: snapshot.bytes, deleted: false, updatedAt: snapshot.createdAt)
        await downloadCopy(document, library: library, revision: snapshot.revision)
    }

    func setAutomatic(_ enabled: Bool) async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount(); syncState?.automatic = enabled; try persistSyncState()
        } catch { status = message(error, title: "") }
    }

    func synchronizeIfEnabled(_ library: LibraryViewModel) async {
        guard !busy else { return }
        await prepareAccount()
        if backupOnClose, (!wifiOnly || automaticNetwork()), !queue.jobs.isEmpty { await retry() }
        guard automatic else { return }
        guard !wifiOnly || automaticNetwork() else { return }
        await synchronize(library, automaticOnly: true)
    }

    /// Closed notebooks only. Server CAS protects uploads; downloads recheck the
    /// local fingerprint under a cloud lease and retain a mandatory local backup.
    func synchronize(_ library: LibraryViewModel, automaticOnly: Bool = false) async {
        guard !busy else { return }; busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount(); await drain(); try await refreshDocuments()
            var completed = 0, skipped = 0
            var problems: [String] = []
            let localIDs = Set((library.notebooks + library.trash).map(\.documentID))
            for book in library.notebooks {
                try Task.checkCancellation()
                // The device library is shared across logins. Never silently
                // enroll unknown local notebooks when a previous user returns.
                // The explicit Sync command is the consent to add new ones.
                if automaticOnly, syncState?.checkpoints[book.documentID] == nil { skipped += 1; continue }
                if queue.jobs.contains(where: { $0.documentID == book.documentID }) { skipped += 1; continue }
                guard EditorLeases.shared.reserveCloud(book.documentID) else { skipped += 1; continue }
                let digest: String
                do {
                    defer { EditorLeases.shared.releaseCloud(book.documentID) }
                    digest = try await library.workspace(book).cloudDigest(metadata: book)
                } catch { problems.append(book.title); continue }
                let remote = documents.first { $0.id == book.documentID }
                let checkpoint = syncState?.checkpoints[book.documentID]
                do {
                    switch AccountSyncPolicy.action(local: digest, remoteRevision: remote?.revision, checkpoint: checkpoint) {
                    case .unchanged: conflicts[book.documentID] = nil
                    case .upload:
                        try await prepare(book, library: library, expectedRevision: remote?.revision ?? 0)
                        await drain()
                        if queue.jobs.contains(where: { $0.documentID == book.documentID }) { skipped += 1 }
                        else { completed += 1; conflicts[book.documentID] = nil }
                    case .download:
                        if let remote { try await install(remote, library: library, expectedLocal: digest); completed += 1 }
                    case .conflict:
                        guard let remote else { problems.append("\(book.title): copia remota rimossa; originale locale conservato"); continue }
                        // A new installation may already have the identical native
                        // export. Verify its package digest before accepting a base.
                        if checkpoint == nil {
                            let verified = try await verifiedArchive(remote)
                            defer { try? FileManager.default.removeItem(at: verified.file) }
                            if verified.digest == digest {
                                try remember(remote, digest: digest); conflicts[book.documentID] = nil; continue
                            }
                        }
                        conflicts[book.documentID] = remote
                    }
                } catch {
                    if error as? CloudBackupFailure == .signedOut { throw error }
                    problems.append("\(book.title): \(error.localizedDescription)")
                }
            }
            // A remote notebook absent on this device keeps its original identity.
            // Local trash IDs are excluded so a deleted notebook never resurrects.
            for remote in documents where !localIDs.contains(remote.id) {
                do { try await install(remote, library: library, expectedLocal: nil); completed += 1 }
                catch {
                    if error as? CloudBackupFailure == .signedOut { throw error }
                    problems.append("\(remote.title): \(error.localizedDescription)")
                }
            }
            _ = try await account()
            status = "\(completed) trasferimenti completati · \(skipped) aperti o in attesa · \(conflicts.count) conflitti."
            if !problems.isEmpty { status += " Avvisi: " + problems.prefix(3).joined(separator: " · ") }
        } catch { status = message(error, title: "") }
    }

    func resolve(_ id: UUID, keepingLocal: Bool, library: LibraryViewModel) async {
        guard !busy, let conflict = conflicts[id] else { return }
        let expectedOwner = owner
        busy = true; operationOwner = nil; defer { finishOperation() }
        do {
            try await selectAccount(); guard expectedOwner == owner else { throw CloudBackupFailure.signedOut }
            try await refreshDocuments()
            guard let remote = documents.first(where: { $0.id == id }) else { throw CloudBackupFailure.conflict }
            guard remote.revision == conflict.revision, remote.checksum == conflict.checksum else {
                conflicts[id] = remote; throw CloudBackupFailure.conflict
            }
            guard let book = library.notebooks.first(where: { $0.documentID == id }) else { throw LibraryFailure.missingItem }
            if keepingLocal {
                try await prepare(book, library: library, expectedRevision: remote.revision); await drain()
                guard !queue.jobs.contains(where: { $0.documentID == id }) else { return }
            } else {
                guard EditorLeases.shared.reserveCloud(id) else { throw CloudBackupJobFailure.open }
                let digest: String
                do { defer { EditorLeases.shared.releaseCloud(id) }; digest = try await library.workspace(book).cloudDigest(metadata: book) }
                try await install(remote, library: library, expectedLocal: digest)
            }
            conflicts[id] = nil; status = "Conflitto risolto per «\(book.title)»."
        } catch { status = message(error, title: "") }
    }

    private func remember(_ remote: CloudDocument, digest: String) throws {
        syncState?.checkpoints[remote.id] = AccountSyncCheckpoint(digest: digest, revision: remote.revision)
        try persistSyncState()
        queue.revisions[remote.id] = remote.revision
        try persist()
    }

    private func install(_ remote: CloudDocument, library: LibraryViewModel, expectedLocal: String?) async throws {
        let verified = try await verifiedArchive(remote)
        defer { try? FileManager.default.removeItem(at: verified.file) }
        _ = try await account()
        guard EditorLeases.shared.reserveCloud(remote.id) else { throw CloudBackupJobFailure.open }
        defer { EditorLeases.shared.releaseCloud(remote.id) }
        _ = try await library.installCloudArchive(verified.file, expectedLocal: expectedLocal, expectedRemote: verified.digest)
        _ = try await account()
        try remember(remote, digest: verified.digest)
    }

    private func verifiedArchive(_ remote: CloudDocument) async throws -> (file: URL, digest: String) {
        guard let checksum = remote.checksum, AccountSyncCheckpoint.validDigest(checksum) else { throw CloudBackupFailure.invalidResponse }
        let (service, token) = try await account()
        let (data, code) = try await exchange(CloudBackupWire.download(studyURL: service.studyURL, token: token, documentID: remote.id))
        guard code == 200 else { throw CloudBackupWire.failure(status: code) }
        _ = try await account()
        let file = try await downloadFile(CloudBackupWire.downloadURL(data, service: service), expectedBytes: remote.bytes)
        do {
            let digest = try await Task.detached(priority: .utility) {
                guard try Self.sha256(file) == checksum else { throw CloudBackupFailure.invalidResponse }
                let staged = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID()).nnbook")
                defer { try? FileManager.default.removeItem(at: staged) }
                try NativeArchive.extract(from: file, to: staged)
                let inspected = try NativePackageInspector.inspect(staged)
                guard inspected.manifest.documentID == remote.id, let metadata = inspected.metadata else { throw CloudBackupFailure.invalidResponse }
                return try SnapshotDigest.package(staged, metadata: metadata)
            }.value
            _ = try await account()
            return (file, digest)
        } catch { try? FileManager.default.removeItem(at: file); throw error }
    }

    // MARK: Steps

    private func prepare(_ book: Notebook, library: LibraryViewModel, expectedRevision: Int? = nil) async throws {
        _ = try await account()
        guard EditorLeases.shared.reserveCloud(book.documentID) else { throw CloudBackupJobFailure.open }
        let snapshot: (archive: URL, digest: String)
        do {
            defer { EditorLeases.shared.releaseCloud(book.documentID) }
            snapshot = try await library.workspace(book).cloudSnapshot(metadata: book)
        }
        let archive = snapshot.archive
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let size = Int64(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size > 0, size <= CloudBackupQueue.maximumBytes else { throw CloudBackupFailure.tooLarge }
        let checksum = try await Task.detached(priority: .utility) { try Self.sha256(archive) }.value
        _ = try await account()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(book.documentID.uuidString)-\(UUID()).nnbackup", destination = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: archive, to: destination)
        let job = CloudBackupJob(documentID: book.documentID, title: book.title, archiveFile: name, checksum: checksum, bytes: size,
                                 expectedRevision: expectedRevision ?? queue.revisions[book.documentID] ?? 0)
        let previous = queue
        let replaced = try queue.enqueue(job)
        do { try persist() }
        catch { queue = previous; try? FileManager.default.removeItem(at: destination); throw error }
        syncState?.uploads[book.documentID] = AccountSyncUpload(digest: snapshot.digest, archiveChecksum: checksum)
        try persistSyncState()
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
                    syncState?.lastBackupAt = Date()
                    syncState?.committed(job, revision: document.revision)
                    try persistSyncState()
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
        var collected: [UUID: CloudDocument] = [:]
        // Fetch all pages before publishing an index. A partial index must not
        // turn existing remote notebooks into apparently new local uploads.
        for offset in stride(from: 0, through: 10_000, by: 50) {
            try Task.checkCancellation()
            let (service, token) = try await account()
            let (data, code) = try await exchange(CloudBackupWire.list(studyURL: service.studyURL, token: token, offset: offset))
            guard code == 200 else { throw CloudBackupWire.failure(status: code) }
            _ = try await account()
            let batch = try CloudBackupWire.documents(data)
            for document in batch {
                if let previous = collected[document.id], previous != document { throw CloudBackupFailure.conflict }
                collected[document.id] = document
            }
            if batch.count < 50 {
                documents = collected.values.filter { !$0.deleted }.sorted { $0.id.uuidString < $1.id.uuidString }
                return
            }
        }
        throw CloudBackupFailure.invalidResponse
    }

    // MARK: Account, files and transport

    static func storageFolder(for owner: CloudBackupOwner, under base: URL) -> URL {
        let identity = owner.studyURL.absoluteString + "\n" + owner.userID.uuidString.lowercased()
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent(key, isDirectory: true)
    }

    private func selectAccount() async throws {
        guard let current = await client.snapshot() else {
            owner = nil; queue = CloudBackupQueue(); documents = []; conflicts = [:]; syncState = nil; throw CloudBackupFailure.signedOut
        }
        let next = CloudBackupOwner(studyURL: current.service.studyURL, userID: current.userID)
        if let operationOwner, operationOwner != next { throw CloudBackupFailure.signedOut }
        operationOwner = next
        guard next != owner else { return }
        let target = Self.storageFolder(for: next, under: baseFolder)
        let file = target.appendingPathComponent("queue.json")
        var restored = CloudBackupQueue(owner: next)
        if FileManager.default.fileExists(atPath: file.path) {
            restored = try JSONDecoder().decode(CloudBackupQueue.self, from: Data(contentsOf: file))
            guard restored.canResume(for: next) else { throw CloudBackupFailure.invalidResponse }
        }
        restored.jobs.removeAll { !FileManager.default.fileExists(atPath: target.appendingPathComponent($0.archiveFile).path) }
        let syncFile = target.appendingPathComponent("sync.json")
        var restoredSync = AccountSyncState(owner: next)
        if FileManager.default.fileExists(atPath: syncFile.path) {
            restoredSync = try JSONDecoder().decode(AccountSyncState.self, from: Data(contentsOf: syncFile))
            guard restoredSync.canResume(for: next) else { throw CloudBackupFailure.invalidResponse }
        }
        folder = target; owner = next; queue = restored; documents = []; conflicts = [:]; syncState = restoredSync
    }

    private func account() async throws -> (service: ManagedAIService, token: String) {
        guard let current = await client.snapshot(),
              owner == CloudBackupOwner(studyURL: current.service.studyURL, userID: current.userID) else { throw CloudBackupFailure.signedOut }
        do {
            let authorization = try await client.authorization(for: current.service.studyURL)
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
        if let transport { let response = try await transport(request); return (response.data, response.status) }
        let session = session(timeout: 60); defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudBackupFailure.unavailable }
        guard data.count <= 2 * 1024 * 1024 else { throw CloudBackupFailure.invalidResponse }
        return (data, http.statusCode)
    }

    private func uploadFile(_ request: URLRequest, file: URL) async throws -> Int {
        if let fileUpload { return try await fileUpload(request, file) }
        let session = session(timeout: 1800); defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.upload(for: request, fromFile: file)
        guard let http = response as? HTTPURLResponse else { throw CloudBackupFailure.unavailable }
        return http.statusCode
    }

    /// Signed links already authorize the download: no account token is sent with them.
    private func downloadFile(_ url: URL, expectedBytes: Int64) async throws -> URL {
        if let fileDownload {
            let file = try await fileDownload(url)
            let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard size == expectedBytes, size > 0, size <= CloudBackupQueue.maximumBytes else {
                try? FileManager.default.removeItem(at: file); throw CloudBackupFailure.invalidResponse
            }
            return file
        }
        let session = session(timeout: 1800); defer { session.finishTasksAndInvalidate() }
        let (temporary, response) = try await session.download(for: URLRequest(url: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { try? FileManager.default.removeItem(at: temporary); throw CloudBackupFailure.unavailable }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID()).nnbackup")
        try FileManager.default.moveItem(at: temporary, to: destination)
        let size = Int64(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size == expectedBytes, size <= CloudBackupQueue.maximumBytes else { try? FileManager.default.removeItem(at: destination); throw CloudBackupFailure.invalidResponse }
        return destination
    }

    nonisolated static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(queue).write(to: folder.appendingPathComponent("queue.json"), options: .atomic)
    }

    private func persistSyncState() throws {
        guard let syncState else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(syncState).write(to: folder.appendingPathComponent("sync.json"), options: .atomic)
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
