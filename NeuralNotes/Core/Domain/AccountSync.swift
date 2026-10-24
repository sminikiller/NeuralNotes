import Foundation

/// Package fingerprints and server revision numbers are different namespaces.
/// Never compare the checksum of an archive to the digest of its extracted files.
public struct AccountSyncCheckpoint: Codable, Equatable, Sendable {
    public let digest: String
    public let revision: Int
    public init(digest: String, revision: Int) { self.digest = digest; self.revision = revision }
    public var isValid: Bool { Self.validDigest(digest) && revision > 0 }
    public static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}

public struct AccountSyncUpload: Codable, Equatable, Sendable {
    public let digest: String
    public let archiveChecksum: String
    public init(digest: String, archiveChecksum: String) { self.digest = digest; self.archiveChecksum = archiveChecksum }
}

public struct AccountSyncState: Codable, Equatable, Sendable {
    public let owner: CloudBackupOwner
    public var automatic = false
    public var checkpoints: [UUID: AccountSyncCheckpoint] = [:]
    public var uploads: [UUID: AccountSyncUpload] = [:]
    public init(owner: CloudBackupOwner) { self.owner = owner }
    public func canResume(for owner: CloudBackupOwner) -> Bool {
        self.owner == owner && checkpoints.values.allSatisfy(\.isValid) && uploads.values.allSatisfy {
            AccountSyncCheckpoint.validDigest($0.digest) && AccountSyncCheckpoint.validDigest($0.archiveChecksum)
        }
    }
    /// Only the exact immutable upload acknowledged by the server can advance
    /// the checkpoint. Edits made while that upload is in flight remain dirty.
    public mutating func committed(_ job: CloudBackupJob, revision: Int) {
        guard let upload = uploads[job.documentID], upload.archiveChecksum == job.checksum, revision > 0 else { return }
        checkpoints[job.documentID] = AccountSyncCheckpoint(digest: upload.digest, revision: revision)
        uploads[job.documentID] = nil
    }
}

public enum AccountSyncPolicy {
    public static func action(local: String, remoteRevision: Int?, checkpoint: AccountSyncCheckpoint?) -> CloudSyncAction {
        guard let remoteRevision else { return checkpoint == nil ? .upload : .conflict }
        guard remoteRevision > 0, let checkpoint, checkpoint.isValid, remoteRevision >= checkpoint.revision else { return .conflict }
        let localChanged = local != checkpoint.digest, remoteChanged = remoteRevision != checkpoint.revision
        switch (localChanged, remoteChanged) {
        case (false, false): return .unchanged
        case (true, false): return .upload
        case (false, true): return .download
        case (true, true): return .conflict
        }
    }
}
