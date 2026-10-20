import Foundation

public struct NotebookOrganization: Codable, Equatable, Sendable {
    public var tags: [String] = []
    public var pinned = false
    public var inbox = false
    public init() {}
    public var isValid: Bool {
        tags.count <= 20 && Set(tags).count == tags.count && tags.allSatisfy { !$0.isEmpty && $0.count <= 32 && !$0.contains(where: { $0.isNewline || $0 == "," }) }
    }
    public static func tags(from text: String) -> [String] {
        var seen = Set<String>()
        return Array(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(20))
    }
}
