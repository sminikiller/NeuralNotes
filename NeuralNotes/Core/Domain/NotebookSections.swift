import Foundation

/// Catalog metadata, independent of page contents. Removed pages keep their
/// assignment so undo/recovery can restore them without changing the section.
public struct NotebookSection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var parentID: UUID?
    public var pageIDs: [UUID]
    public init(id: UUID = UUID(), title: String, parentID: UUID? = nil, pageIDs: [UUID] = []) {
        self.id = id; self.title = title; self.parentID = parentID; self.pageIDs = pageIDs
    }
}

public enum NotebookSections {
    public static func validate(_ sections: [NotebookSection]) throws {
        guard sections.count <= 1000, Set(sections.map(\.id)).count == sections.count else { throw LibraryFailure.corruptDocument }
        let parents = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0) })
        var assigned = Set<UUID>()
        for section in sections {
            guard (try? LibraryName.validated(section.title)) == section.title,
                  section.pageIDs.count <= 50_000 else { throw LibraryFailure.corruptDocument }
            for pageID in section.pageIDs {
                guard assigned.insert(pageID).inserted else { throw LibraryFailure.corruptDocument }
            }
            var cursor: UUID? = section.id, visited = Set<UUID>()
            while let id = cursor {
                guard visited.insert(id).inserted, visited.count <= 12, let ancestor = parents[id] else { throw LibraryFailure.corruptDocument }
                cursor = ancestor.parentID
            }
        }
    }

    /// Iterative, bounded traversal; malformed external metadata cannot recurse.
    public static func outline(_ sections: [NotebookSection]) -> [(section: NotebookSection, depth: Int)] {
        guard (try? validate(sections)) != nil else { return [] }
        var result: [(NotebookSection, Int)] = []
        var stack = sections.filter { $0.parentID == nil }.reversed().map { ($0, 0) }
        while let (section, depth) = stack.popLast() {
            result.append((section, depth))
            stack.append(contentsOf: sections.filter { $0.parentID == section.id }.reversed().map { ($0, depth + 1) })
        }
        return result
    }

    public static func pages(in id: UUID, sections: [NotebookSection], includeChildren: Bool = true) -> Set<UUID> {
        let rows = outline(sections)
        guard let start = rows.firstIndex(where: { $0.section.id == id }) else { return [] }
        var pages = Set(rows[start].section.pageIDs)
        guard includeChildren else { return pages }
        for row in rows.dropFirst(start + 1) {
            if row.depth <= rows[start].depth { break }
            pages.formUnion(row.section.pageIDs)
        }
        return pages
    }
}
