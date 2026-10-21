import Foundation

public enum SystemSearchIdentity {
    private static let prefix = "neuralnotes:document:"
    public static func identifier(documentID: UUID) -> String { prefix + documentID.uuidString }
    public static func documentID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }
}
