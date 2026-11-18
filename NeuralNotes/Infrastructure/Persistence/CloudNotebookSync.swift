import Foundation
import CloudKit
import CryptoKit
import Observation
import NeuralNotesCore

enum CloudNotebookFailure: LocalizedError {
    case configuration, account, restricted, temporarilyUnavailable, invalidSnapshot
    var errorDescription: String? {
        switch self {
        case .configuration: return "La sincronizzazione CloudKit richiede una build firmata con iCloud. Puoi salvare manualmente un backup in File → iCloud Drive."
        case .account: return "Accedi a iCloud nelle impostazioni dell’iPad e abilita iCloud per NeuralNotes."
        case .restricted: return "L’account o il dispositivo limita l’accesso a iCloud."
        case .temporarilyUnavailable: return "iCloud è temporaneamente non disponibile. Riprova dopo aver controllato la connessione."
        case .invalidSnapshot: return "La copia iCloud non è completa. Il quaderno locale è stato conservato."
        }
    }
}

@MainActor @Observable
final class CloudNotebookSync {
    static let shared = CloudNotebookSync()
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        Bundle.main.object(forInfoDictionaryKey: "NNCloudSigned") as? Bool == true
        #endif
    }
    var busy = false
    private(set) var status = CloudNotebookSync.isSupported ? "Verifica l’account Apple" : (CloudNotebookFailure.configuration.errorDescription ?? "")
    private(set) var connected = false
    private(set) var automatic = false
    private(set) var syncedDates: [UUID: Date] = [:]
    private(set) var lastSyncAt: Date?
    var conflicts: [UUID: CKRecord] = [:]
    @ObservationIgnored private var database: CKDatabase?
    @ObservationIgnored private var accountScope: String?
    @ObservationIgnored private var accountGeneration = UUID()
    @ObservationIgnored private var accountObserver: Task<Void, Never>?
    private let automaticKey = "cloud.automatic.owner"
    private var defaults: UserDefaults { .standard }
    init() {
        accountObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard !Task.isCancelled else { return }
                self?.clearAccount()
                self?.status = "Account Apple cambiato. Verifica la connessione a iCloud."
            }
        }
    }
    deinit { accountObserver?.cancel() }
    private func requireAccount(_ generation: UUID) throws {
        guard generation == accountGeneration, accountScope != nil else { throw CloudNotebookFailure.account }
    }

    private func clearAccount() {
        database = nil; accountScope = nil; conflicts = [:]; accountGeneration = UUID()
        connected = false; automatic = false; syncedDates = [:]; lastSyncAt = nil
    }

    func refreshConnection() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { _ = try await connect(); status = "Account Apple collegato a iCloud." }
        catch { status = error.localizedDescription }
    }

    func setAutomatic(_ enabled: Bool, library: LibraryViewModel) async {
        guard !busy else { return }
        if !enabled {
            defaults.removeObject(forKey: automaticKey)
            automatic = false
            return
        }
        await refreshConnection()
        guard connected, let accountScope else { return }
        defaults.set(accountScope, forKey: automaticKey)
        automatic = true
        await synchronizeIfEnabled(library)
    }

    func synchronizeIfEnabled(_ library: LibraryViewModel) async {
        guard Self.isSupported, defaults.string(forKey: automaticKey) != nil else { return }
        await synchronize(library, automaticOnly: true)
    }

    @ObservationIgnored private let indexID = CKRecord.ID(recordName: "library.v1")
    private func connect() async throws -> CKDatabase {
        guard Self.isSupported else { throw CloudNotebookFailure.configuration }
        let generation = accountGeneration
        let container = CKContainer(identifier: "iCloud.com.lorenzominichilli.neuralnotes")
        let availability = try await container.accountStatus()
        guard generation == accountGeneration else { throw CloudNotebookFailure.account }
        switch availability {
        case .available: break
        case .noAccount: clearAccount(); throw CloudNotebookFailure.account
        case .restricted: clearAccount(); throw CloudNotebookFailure.restricted
        case .couldNotDetermine, .temporarilyUnavailable: throw CloudNotebookFailure.temporarilyUnavailable
        @unknown default: throw CloudNotebookFailure.temporarilyUnavailable
        }
        let user = try await container.userRecordID().recordName
        guard generation == accountGeneration else { throw CloudNotebookFailure.account }
        let scope = SHA256.hash(data: Data(user.utf8)).map { String(format: "%02x", $0) }.joined()
        if accountScope != scope { clearAccount(); accountScope = scope }
        connected = true
        automatic = defaults.string(forKey: automaticKey) == scope
        let value = database ?? container.privateCloudDatabase
        database = value
        return value
    }
    private func record(_ id: CKRecord.ID, database: CKDatabase) async throws -> CKRecord? {
        do { return try await database.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }
    private func save(_ record: CKRecord, database: CKDatabase) async throws -> CKRecord {
        let generation = accountGeneration; try requireAccount(generation)
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
        try requireAccount(generation)
        guard let value = result.saveResults[record.recordID] else { throw CloudNotebookFailure.invalidSnapshot }
        return try value.get()
    }
    private func checkpoint(_ id: UUID) -> CloudSyncCheckpoint? {
        UserDefaults.standard.data(forKey: "cloud.checkpoint.v2.\(accountScope ?? "unconnected").\(id)").flatMap { try? JSONDecoder().decode(CloudSyncCheckpoint.self, from: $0) }
    }
    private func remember(_ id: UUID, digest: String) {
        guard accountScope != nil else { return }
        if let bytes = try? JSONEncoder().encode(CloudSyncCheckpoint(local: digest, remote: digest)) { UserDefaults.standard.set(bytes, forKey: "cloud.checkpoint.v2.\(accountScope ?? "unconnected").\(id)") }
    }
    func synchronize(_ library: LibraryViewModel, documentID: UUID? = nil, automaticOnly: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let database = try await connect()
            guard !automaticOnly || automatic else { return }
            let generation = accountGeneration
            status = "Sincronizzazione iCloud in corso…"
            var registered: [String] = []
            var deferred = 0
            for book in library.notebooks where documentID == nil || book.documentID == documentID {
                try Task.checkCancellation(); try requireAccount(generation)
                guard EditorLeases.shared.reserveCloud(book.documentID) else { deferred += 1; continue }
                defer { EditorLeases.shared.releaseCloud(book.documentID) }
                let workspace = try library.workspace(book)
                let localDigest = try await workspace.cloudDigest(metadata: book)
                try requireAccount(generation)
                let remote = try await record(CKRecord.ID(recordName: book.documentID.uuidString), database: database)
                try requireAccount(generation)
                let remoteDigest = remote?["digest"] as? String
                switch CloudSyncPolicy.action(local: localDigest, remote: remoteDigest, checkpoint: checkpoint(book.documentID)) {
                case .unchanged: remember(book.documentID, digest: localDigest)
                case .upload:
                    let snapshot = try await workspace.cloudSnapshot(metadata: book)
                    defer { try? FileManager.default.removeItem(at: snapshot.archive.deletingLastPathComponent()) }
                    try requireAccount(generation)
                    // Publish the ID first. Another device can skip a missing snapshot and retry.
                    try await register([book.documentID.uuidString], database: database, generation: generation)
                    _ = try await upload(snapshot.archive, digest: snapshot.digest, book: book, previous: remote, database: database)
                    remember(book.documentID, digest: snapshot.digest)
                case .download:
                    guard let remote, let digest = remoteDigest else { throw CloudNotebookFailure.invalidSnapshot }
                    let archive = try await download(remote, database: database); defer { try? FileManager.default.removeItem(at: archive) }
                    try requireAccount(generation)
                    _ = try await library.installCloudArchive(archive, expectedLocal: localDigest, expectedRemote: digest) { try self.requireAccount(generation) }
                    try requireAccount(generation)
                    remember(book.documentID, digest: digest)
                case .conflict: if let remote { conflicts[book.documentID] = remote }; continue
                }
                conflicts.removeValue(forKey: book.documentID)
                syncedDates[book.documentID] = Date()
                registered.append(book.documentID.uuidString)
            }
            if documentID == nil {
                let index = try await record(indexID, database: database)
                let ids = index?["books"] as? [String] ?? []
                try requireAccount(generation)
                let known = Set((library.notebooks + library.trash).map { $0.documentID.uuidString })
                for name in Set(ids).subtracting(known).sorted() {
                    try Task.checkCancellation(); try requireAccount(generation)
                    guard let id = UUID(uuidString: name), EditorLeases.shared.reserveCloud(id) else { continue }
                    defer { EditorLeases.shared.releaseCloud(id) }
                    guard let remote = try await record(CKRecord.ID(recordName: name), database: database), let digest = remote["digest"] as? String else { continue }
                    let archive = try await download(remote, database: database); defer { try? FileManager.default.removeItem(at: archive) }
                    try requireAccount(generation)
                    _ = try await library.installCloudArchive(archive, expectedLocal: nil, expectedRemote: digest) { try self.requireAccount(generation) }
                    try requireAccount(generation)
                    remember(id, digest: digest)
                    syncedDates[id] = Date()
                }
            }
            try await register(registered, database: database, generation: generation)
            lastSyncAt = Date()
            if !conflicts.isEmpty { status = "\(conflicts.count) conflitti: entrambe le versioni sono conservate." }
            else if deferred > 0 { status = "\(deferred) quaderni aperti o occupati. Chiudili e riprova." }
            else { status = documentID == nil ? "Controllo iCloud completato." : "Quaderno sincronizzato con iCloud." }
        } catch is CancellationError { status = "Sincronizzazione sospesa; copie locali conservate." }
        catch { status = error.localizedDescription }
    }
    func importConflictCopy(_ id: UUID, library: LibraryViewModel) async {
        guard !busy, let remote = conflicts[id], let scope = accountScope else { return }; busy = true; defer { busy = false }
        do {
            let database = try await connect(); let generation = accountGeneration
            guard scope == accountScope else { throw CloudNotebookFailure.account }
            let archive = try await download(remote, database: database)
            defer { try? FileManager.default.removeItem(at: archive) }
            try requireAccount(generation)
            await library.importNotebook(from: archive)
            if library.errorMessage == nil { status = "Copia remota importata. Puoi ancora scegliere quale versione sincronizzare per il quaderno originale." }
        } catch { status = error.localizedDescription }
    }
    func resolve(_ id: UUID, keepingLocal: Bool, library: LibraryViewModel) async {
        guard !busy, let conflict = conflicts[id], let scope = accountScope, let book = library.notebooks.first(where: { $0.documentID == id }),
              EditorLeases.shared.reserveCloud(id) else { return }
        busy = true; defer { busy = false; EditorLeases.shared.releaseCloud(id) }
        do {
            let database = try await connect(); let generation = accountGeneration
            guard scope == accountScope else { throw CloudNotebookFailure.account }
            guard let latest = try await record(conflict.recordID, database: database) else { throw CloudNotebookFailure.invalidSnapshot }
            guard latest.recordChangeTag == conflict.recordChangeTag else { conflicts[id] = latest; status = "iCloud è cambiato di nuovo. Controlla entrambe le versioni prima di scegliere."; return }
            let workspace = try library.workspace(book), snapshot = try await workspace.cloudSnapshot(metadata: book)
            defer { try? FileManager.default.removeItem(at: snapshot.archive.deletingLastPathComponent()) }
            try requireAccount(generation)
            if keepingLocal {
                _ = try await upload(snapshot.archive, digest: snapshot.digest, book: book, previous: latest, database: database); remember(id, digest: snapshot.digest)
            } else {
                guard let digest = latest["digest"] as? String else { throw CloudNotebookFailure.invalidSnapshot }
                let archive = try await download(latest, database: database); defer { try? FileManager.default.removeItem(at: archive) }
                try requireAccount(generation)
                _ = try await library.installCloudArchive(archive, expectedLocal: snapshot.digest, expectedRemote: digest) { try self.requireAccount(generation) }
                try requireAccount(generation)
                remember(id, digest: digest)
            }
            syncedDates[id] = Date()
            conflicts.removeValue(forKey: id); status = "Conflitto risolto. Le copie di sicurezza restano disponibili."
        } catch { status = error.localizedDescription }
    }
    private func upload(_ archive: URL, digest: String, book: Notebook, previous: CKRecord?, database: CKDatabase) async throws -> CKRecord {
        let generation = accountGeneration; try requireAccount(generation)
        let input = try FileHandle(forReadingFrom: archive); defer { try? input.close() }
        var chunks: [String] = [], publishing = false
        defer {
            // A failed response after publishing can still mean CloudKit committed the record.
            // Keep its chunks so that a retry can read the complete snapshot.
            if !publishing && generation == accountGeneration {
                Task { await deleteChunks(chunks, database: database, generation: generation) }
            }
        }
        while let bytes = try input.read(upToCount: 8 * 1024 * 1024), !bytes.isEmpty {
            try Task.checkCancellation(); try requireAccount(generation)
            let name = "chunk.\(UUID())", file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try bytes.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
            let part = CKRecord(recordType: "NNChunk", recordID: CKRecord.ID(recordName: name)); part["asset"] = CKAsset(fileURL: file)
            _ = try await save(part, database: database); chunks.append(name)
        }
        try requireAccount(generation)
        let expired = previous?["previousChunks"] as? [String] ?? []
        let value = previous ?? CKRecord(recordType: "NNNotebook", recordID: CKRecord.ID(recordName: book.documentID.uuidString))
        value["previousChunks"] = (previous?["chunks"] as? [String] ?? []) as CKRecordValue
        value["chunks"] = chunks as CKRecordValue; value["digest"] = digest as CKRecordValue
        value["title"] = book.title as CKRecordValue; value["updated"] = Date() as CKRecordValue
        publishing = true
        let result = try await save(value, database: database)
        await deleteChunks(expired, database: database, generation: generation)
        try requireAccount(generation)
        return result
    }
    private func deleteChunks(_ names: [String], database: CKDatabase, generation: UUID) async {
        let chunks = names.filter { $0.hasPrefix("chunk.") }
        for offset in stride(from: 0, to: chunks.count, by: 200) {
            guard generation == accountGeneration else { return }
            let ids = chunks[offset..<min(chunks.count, offset + 200)].map { CKRecord.ID(recordName: $0) }
            _ = try? await database.modifyRecords(saving: [], deleting: ids, atomically: false)
        }
    }
    private func download(_ record: CKRecord, database: CKDatabase) async throws -> URL {
        guard let chunks = record["chunks"] as? [String], !chunks.isEmpty, chunks.count <= 4096 else { throw CloudNotebookFailure.invalidSnapshot }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID()).nnbackup")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let output = try FileHandle(forWritingTo: file); var complete = false, total = 0
        defer { try? output.close(); if !complete { try? FileManager.default.removeItem(at: file) } }
        for name in chunks {
            try Task.checkCancellation()
            guard name.hasPrefix("chunk."), let part = try await self.record(CKRecord.ID(recordName: name), database: database),
                  let asset = part["asset"] as? CKAsset, let url = asset.fileURL else { throw CloudNotebookFailure.invalidSnapshot }
            let values = try url.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? 0) <= 8 * 1024 * 1024 else { throw CloudNotebookFailure.invalidSnapshot }
            let bytes = try Data(contentsOf: url); total += bytes.count
            guard total <= 16 * 1024 * 1024 * 1024 else { throw NativeArchiveFailure.limit }; try output.write(contentsOf: bytes)
        }
        try output.synchronize(); complete = true; return file
    }
    private func register(_ names: [String], database: CKDatabase, generation: UUID) async throws {
        try requireAccount(generation)
        guard !names.isEmpty else { return }
        for attempt in 0..<3 {
            let index = try await record(indexID, database: database) ?? CKRecord(recordType: "NNLibrary", recordID: indexID)
            try requireAccount(generation)
            let current = Set(index["books"] as? [String] ?? [])
            let updated = current.union(names)
            guard current != updated else { return }
            index["books"] = updated.sorted() as CKRecordValue
            do { _ = try await save(index, database: database); return }
            catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 { continue }
        }
    }
}
