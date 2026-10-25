import Foundation
import CloudKit
import CryptoKit
import Observation
import NeuralNotesCore

enum CloudNotebookFailure: LocalizedError {
    case configuration, account, invalidSnapshot
    var errorDescription: String? {
        switch self {
        case .configuration: return "iCloud richiede l’app firmata con il contenitore CloudKit abilitato. Il progetto Xcode è predisposto; il runner Swift Playground e il simulatore non attivano questa connessione."
        case .account: return "Accedi a iCloud nelle impostazioni dell’iPad e abilita iCloud per NeuralNotes."
        case .invalidSnapshot: return "La copia iCloud non è completa. Il quaderno locale è stato conservato."
        }
    }
}

@MainActor @Observable
final class CloudNotebookSync {
    static let shared = CloudNotebookSync()
    var busy = false
    var status = "iCloud non connesso"
    var conflicts: [UUID: CKRecord] = [:]
    @ObservationIgnored private var database: CKDatabase?
    @ObservationIgnored private var accountScope: String?
    @ObservationIgnored private var accountGeneration = UUID()
    @ObservationIgnored private var accountObserver: Task<Void, Never>?
    init() {
        accountObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard !Task.isCancelled else { return }
                self?.database = nil; self?.accountScope = nil; self?.conflicts = [:]
                self?.accountGeneration = UUID(); self?.status = "Account iCloud cambiato. Ricollega la sincronizzazione."
            }
        }
    }
    deinit { accountObserver?.cancel() }
    private func requireAccount(_ generation: UUID) throws {
        guard generation == accountGeneration, accountScope != nil else { throw CloudNotebookFailure.account }
    }

    @ObservationIgnored private let indexID = CKRecord.ID(recordName: "library.v1")
    private func connect() async throws -> CKDatabase {
        #if targetEnvironment(simulator)
        throw CloudNotebookFailure.configuration
        #else
        guard Bundle.main.object(forInfoDictionaryKey: "NNCloudSigned") as? Bool == true else { throw CloudNotebookFailure.configuration }
        let container = CKContainer(identifier: "iCloud.com.lorenzominichilli.neuralnotes")
        guard try await container.accountStatus() == .available else { throw CloudNotebookFailure.account }
        let generation = accountGeneration
        let user = try await container.userRecordID().recordName
        guard generation == accountGeneration else { throw CloudNotebookFailure.account }
        let scope = SHA256.hash(data: Data(user.utf8)).map { String(format: "%02x", $0) }.joined()
        if accountScope != scope { conflicts = [:]; accountScope = scope; database = nil }
        let value = database ?? container.privateCloudDatabase; database = value; return value
        #endif
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
    func synchronize(_ library: LibraryViewModel) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let database = try await connect(); let generation = accountGeneration; status = "Sincronizzazione in corso…"
            var registered: [String] = []
            for book in library.notebooks {
                try Task.checkCancellation(); try requireAccount(generation)
                guard EditorLeases.shared.reserveCloud(book.documentID) else { continue }
                defer { EditorLeases.shared.releaseCloud(book.documentID) }
                let workspace = try library.workspace(book)
                let localDigest = try await workspace.cloudDigest(metadata: book)
                let remote = try await record(CKRecord.ID(recordName: book.documentID.uuidString), database: database)
                let remoteDigest = remote?["digest"] as? String
                switch CloudSyncPolicy.action(local: localDigest, remote: remoteDigest, checkpoint: checkpoint(book.documentID)) {
                case .unchanged: remember(book.documentID, digest: localDigest)
                case .upload:
                    let snapshot = try await workspace.cloudSnapshot(metadata: book)
                    defer { try? FileManager.default.removeItem(at: snapshot.archive.deletingLastPathComponent()) }
                    _ = try await upload(snapshot.archive, digest: snapshot.digest, book: book, previous: remote, database: database)
                    remember(book.documentID, digest: snapshot.digest)
                case .download:
                    guard let remote, let digest = remoteDigest else { throw CloudNotebookFailure.invalidSnapshot }
                    let archive = try await download(remote, database: database); defer { try? FileManager.default.removeItem(at: archive) }
                    try requireAccount(generation)
                _ = try await library.installCloudArchive(archive, expectedLocal: localDigest, expectedRemote: digest)
                    remember(book.documentID, digest: digest)
                case .conflict: if let remote { conflicts[book.documentID] = remote }; continue
                }
                registered.append(book.documentID.uuidString)
            }
            let index = try await record(indexID, database: database)
            let ids = index?["books"] as? [String] ?? []
            try requireAccount(generation)
            let known = Set((library.notebooks + library.trash).map { $0.documentID.uuidString })
            for name in ids where !known.contains(name) {
                guard let id = UUID(uuidString: name), EditorLeases.shared.reserveCloud(id) else { continue }
                defer { EditorLeases.shared.releaseCloud(id) }
                guard let remote = try await record(CKRecord.ID(recordName: name), database: database), let digest = remote["digest"] as? String else { continue }
                let archive = try await download(remote, database: database); defer { try? FileManager.default.removeItem(at: archive) }
                try requireAccount(generation)
                _ = try await library.installCloudArchive(archive, expectedLocal: nil, expectedRemote: digest); remember(id, digest: digest)
            }
            try requireAccount(generation)
            try await register(registered, database: database)
            status = conflicts.isEmpty ? "Quaderni sincronizzati. Quelli aperti vengono riprovati dopo la chiusura." : "\(conflicts.count) conflitti: entrambe le versioni sono conservate."
        } catch is CancellationError { status = "Sincronizzazione sospesa; copie locali conservate." }
        catch { status = error.localizedDescription }
    }
    func importConflictCopy(_ id: UUID, library: LibraryViewModel) async {
        guard !busy, let remote = conflicts[id] else { return }; busy = true; defer { busy = false }
        do {
            let database = try await connect(); let generation = accountGeneration
            let archive = try await download(remote, database: database)
            defer { try? FileManager.default.removeItem(at: archive) }
            try requireAccount(generation)
            await library.importNotebook(from: archive)
            if library.errorMessage == nil { conflicts.removeValue(forKey: id); status = "Copia remota importata come quaderno indipendente. Il conflitto originale resta protetto finché scegli quale versione mantenere." }
        } catch { status = error.localizedDescription }
    }
    func resolve(_ id: UUID, keepingLocal: Bool, library: LibraryViewModel) async {
        guard !busy, let conflict = conflicts[id], let book = library.notebooks.first(where: { $0.documentID == id }),
              EditorLeases.shared.reserveCloud(id) else { return }
        busy = true; defer { busy = false; EditorLeases.shared.releaseCloud(id) }
        do {
            let database = try await connect(); let generation = accountGeneration
            guard let latest = try await record(conflict.recordID, database: database) else { throw CloudNotebookFailure.invalidSnapshot }
            guard latest.recordChangeTag == conflict.recordChangeTag else { conflicts[id] = latest; status = "iCloud è cambiato di nuovo. Controlla entrambe le versioni prima di scegliere."; return }
            let workspace = try library.workspace(book), snapshot = try await workspace.cloudSnapshot(metadata: book)
            defer { try? FileManager.default.removeItem(at: snapshot.archive.deletingLastPathComponent()) }
            if keepingLocal {
                _ = try await upload(snapshot.archive, digest: snapshot.digest, book: book, previous: latest, database: database); remember(id, digest: snapshot.digest)
            } else {
                guard let digest = latest["digest"] as? String else { throw CloudNotebookFailure.invalidSnapshot }
                let archive = try await download(latest, database: database); defer { try? FileManager.default.removeItem(at: archive) }
                try requireAccount(generation)
                _ = try await library.installCloudArchive(archive, expectedLocal: snapshot.digest, expectedRemote: digest); remember(id, digest: digest)
            }
            conflicts.removeValue(forKey: id); status = "Conflitto risolto. Le copie di sicurezza restano disponibili."
        } catch { status = error.localizedDescription }
    }
    private func upload(_ archive: URL, digest: String, book: Notebook, previous: CKRecord?, database: CKDatabase) async throws -> CKRecord {
        let generation = accountGeneration; try requireAccount(generation)
        let input = try FileHandle(forReadingFrom: archive); defer { try? input.close() }
        var chunks: [String] = [], committed = false
        defer {
            if !committed && generation == accountGeneration { Task { _ = try? await database.modifyRecords(saving: [], deleting: chunks.map { CKRecord.ID(recordName: $0) }, atomically: false) } }
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
        let result = try await save(value, database: database); committed = true
        for offset in stride(from: 0, to: expired.count, by: 200) {
            let ids = expired[offset..<min(expired.count, offset + 200)].map { CKRecord.ID(recordName: $0) }
            _ = try? await database.modifyRecords(saving: [], deleting: ids, atomically: false)
        }
        return result
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
    private func register(_ names: [String], database: CKDatabase) async throws {
        for attempt in 0..<3 {
            let index = try await record(indexID, database: database) ?? CKRecord(recordType: "NNLibrary", recordID: indexID)
            index["books"] = Array(Set((index["books"] as? [String] ?? []) + names)).sorted() as CKRecordValue
            do { _ = try await save(index, database: database); return }
            catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 { continue }
        }
    }
}
