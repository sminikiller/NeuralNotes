import Foundation

public struct CloudSyncCheckpoint: Codable, Sendable {
    public let local: String
    public let remote: String
    public init(local: String, remote: String) { self.local = local; self.remote = remote }
}
public enum CloudSyncAction: Equatable, Sendable { case upload, download, unchanged, conflict }
public enum CloudSyncPolicy {
    public static func action(local: String, remote: String?, checkpoint: CloudSyncCheckpoint?) -> CloudSyncAction {
        guard let remote else { return .upload }
        if local == remote { return .unchanged }
        guard let checkpoint else { return .conflict }
        if remote == checkpoint.remote { return .upload }
        if local == checkpoint.local { return .download }
        return .conflict
    }
}
